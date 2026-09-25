#!/usr/bin/env bash
# Offline dev instance of Dank Calendar on a scratch copy of the real data.
#
#   dev-instance.sh start <checkout>   build <checkout>/core, stop dcal.service, copy the real
#                                      data, run the build as the transient unit dankcal-dev
#   dev-instance.sh ipc <method> [k=v…]  `dcal ipc` against the dev instance only
#   dev-instance.sh screenshot <png>   show the dev window and capture only its area (Hyprland)
#   dev-instance.sh probe              try to reach the internet from inside the dev instance's
#                                      network namespace (must fail)
#   dev-instance.sh status             state of dankcal-dev and dcal, versions of the dev DB copy
#   dev-instance.sh stop               stop dankcal-dev, check the real DB is unchanged, no dev
#                                      process is left and dcal.service is active again;
#                                      exits 1 unless it prints "dev instance stopped cleanly"
#                                      or leaves running one started while it waited
#
# <checkout> is the absolute path of any checkout of this repo (the main one or a linked
# worktree with its submodule initialised). Its QML runs from <checkout>/quickshell.
# One dev instance per machine: start and stop each hold the lock $LOCK while they run (never
# passed to the dev instance; start fails if it is taken, stop waits up to 180s), and start
# refuses while dankcal-dev is active or activating.
#
# Isolation:
#   data     XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, XDG_CACHE_HOME point under
#            $ROOT/home, seeded by copying the real dankcal dirs while dcal.service is
#            stopped. The real dirs are only read (cp, sha256sum); sqlite3 only ever opens the
#            copies. A clean stop deletes the copy (it holds the accounts' tokens).
#   offline  the unit runs with PrivateNetwork=yes: its only interface is loopback. systemd
#            silently runs a unit without it when the namespace can't be set up, so `guard`
#            execs dcal only after checking loopback is the only interface it can see. `probe`
#            shows it from inside. The copied keyring keeps the tokens, so providers fail as
#            offline, never as signed out.
#   D-Bus    the session bus is shared with the desktop. start (and guard) refuse while a
#            Secret Service or Evolution Data Server is on it, or the copy has an Evolution
#            account: either would reach real credentials or sync outside the namespace. One
#            that appears mid-run is not prevented; stop reports one still on the bus.
#   process  dankcal-dev Conflicts= dcal.service, and After= orders the stop of one before the
#            start of the other, so the two never run together (a live dcal started next to
#            the dev one takes its QML dir from $XDG_RUNTIME_DIR/dankcal.path). Stopping the
#            unit kills its whole cgroup (daemon and qs); its ExecStopPost records the real
#            DB's checksum and starts dcal.service again, also when the dev instance crashes
#            or hits RuntimeMaxSec.
set -euo pipefail
umask 077

BASE="/tmp/claude-$(id -u)"
ROOT="$BASE/dankcal-dev"
LOCK="$BASE/dankcal-dev.lock"
UNIT=dankcal-dev.service
LIVE=dcal.service
REAL_DATA="$HOME/.local/share/dankcal"
REAL_CONFIG="$HOME/.config/dankcal"
REAL_STATE="$HOME/.local/state/dankcal"
MAX_RUNTIME=2h

die() { echo "dev-instance: $*" >&2; exit 1; }

dev_pid() { systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null || echo 0; }

dev_socket() {
	local pid
	pid=$(dev_pid)
	[ "$pid" -gt 0 ] || die "$UNIT is not running"
	echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dankcal-$pid.sock"
}

# goose version and PRAGMA user_version of a *copy* of the DB.
db_versions() {
	printf 'goose_version=%s user_version=%s\n' \
		"$(sqlite3 "$1" 'SELECT max(version_id) FROM goose_db_version WHERE is_applied;')" \
		"$(sqlite3 "$1" 'PRAGMA user_version;')"
}

# Session-bus names that would let the dev daemon reach real credentials or sync outside its
# network namespace. Prints them; fails if the bus can't be listed.
shared_dbus_names() {
	local names
	names=$(busctl --user list --no-legend) || die "cannot list the session bus (busctl failed)"
	awk '{print $1}' <<<"$names" | grep -E '^(org\.freedesktop\.secrets|org\.gnome\.evolution\.dataserver\..*)$' || true
}

scratch_ok() {
	mkdir -p "$BASE"
	[ -O "$BASE" ] && [ ! -L "$BASE" ] || die "$BASE is not a directory owned by $(id -un)"
	[ ! -L "$ROOT" ] || die "$ROOT is a symlink"
	mkdir -p "$ROOT"
	[ -O "$ROOT" ] || die "$ROOT is not owned by $(id -un)"
	chmod 700 "$BASE" "$ROOT"
}

cmd_start() {
	local checkout=${1:-} shared
	[ -n "$checkout" ] || die "usage: dev-instance.sh start <absolute checkout path>"
	case "$checkout" in /*) ;; *) die "checkout path must be absolute: $checkout" ;; esac
	checkout=${checkout%/}
	[ "$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null)" = "$checkout" ] ||
		die "$checkout is not the top of a git checkout"
	[ -d "$checkout/core/cmd/dcal" ] || die "$checkout has no core/cmd/dcal"
	[ -f "$checkout/quickshell/DankCommon/Widgets/DankIcon.qml" ] ||
		die "DankCommon missing in $checkout: initialise its submodule as in verify-change section 4"
	case "$(systemctl --user is-active "$UNIT" || true)" in
	active | activating | reloading | deactivating) die "$UNIT is running; stop it first" ;;
	esac
	shared=$(shared_dbus_names)
	[ -z "$shared" ] || die "on the session bus, would be shared with the dev instance: $shared"

	echo "== build $checkout"
	mkdir -p "$ROOT/bin"
	(cd "$checkout/core" && CGO_ENABLED=0 go build -o "$ROOT/bin/dcal" ./cmd/dcal) 9>&-
	install -m 0755 "$(readlink -f "$0")" "$ROOT/bin/dev-instance.sh"
	echo "$checkout" >"$ROOT/checkout"

	echo "== stop $LIVE and copy the real data"
	systemctl --user stop "$LIVE"
	# Until the unit exists (its ExecStopPost takes over), any failure restarts the live one.
	trap 'systemctl --user start "$LIVE"' EXIT
	rm -rf "$ROOT/home" "$ROOT/after" "$ROOT/real-before.sha256" "$ROOT/real-after.sha256"
	mkdir -p "$ROOT/home/data" "$ROOT/home/config" "$ROOT/home/state" "$ROOT/home/cache"
	sha256sum "$REAL_DATA"/dankcal.db* >"$ROOT/real-before.sha256"
	cp -a "$REAL_DATA" "$ROOT/home/data/"
	[ ! -d "$REAL_CONFIG" ] || cp -a "$REAL_CONFIG" "$ROOT/home/config/"
	[ ! -d "$REAL_STATE" ] || cp -a "$REAL_STATE" "$ROOT/home/state/"
	cat "$ROOT/real-before.sha256"
	echo "real DB before: $(db_versions "$ROOT/home/data/dankcal/dankcal.db")"
	[ "$(sqlite3 "$ROOT/home/data/dankcal/dankcal.db" "SELECT count(*) FROM accounts WHERE kind = 'evolution';")" = 0 ] ||
		die "the data has an Evolution account: EDS syncs over the shared session bus, outside the namespace"

	echo "== start $UNIT"
	systemd-run --user --unit="$UNIT" --collect --quiet \
		-p PrivateNetwork=yes \
		-p Conflicts="$LIVE" -p After="$LIVE" \
		-p RuntimeMaxSec="$MAX_RUNTIME" \
		-p ExecStopPost="$ROOT/bin/dev-instance.sh on-stop" \
		-E XDG_DATA_HOME="$ROOT/home/data" \
		-E XDG_CONFIG_HOME="$ROOT/home/config" \
		-E XDG_STATE_HOME="$ROOT/home/state" \
		-E XDG_CACHE_HOME="$ROOT/home/cache" \
		-E DANKCAL_DB_PATH="$ROOT/home/data/dankcal/dankcal.db" \
		-E DCAL_ENABLE_HOTRELOAD=1 \
		"$ROOT/bin/dev-instance.sh" guard "$ROOT/bin/dcal" run -c "$checkout/quickshell" 9>&-
	trap - EXIT

	local sock
	for _ in $(seq 1 30); do
		systemctl --user is-active --quiet "$UNIT" || break
		sock=$(dev_socket)
		if DANKCAL_SOCKET=$sock "$ROOT/bin/dcal" ipc accounts.list >/dev/null 2>&1; then
			echo "dev instance ready: pid $(dev_pid), socket $sock"
			echo "logs: journalctl --user -u $UNIT -I --no-pager"
			return 0
		fi
		sleep 1
	done
	journalctl --user -u "$UNIT" --no-pager -n 40 || true
	(cmd_stop) || true
	die "dev instance exited or did not answer on its socket within 30s"
}

# ExecStart wrapper of dankcal-dev: refuse to run dcal with any network but loopback, or next
# to a shared Secret Service / EDS.
cmd_guard() {
	local ifaces shared
	ifaces=$(tail -n +3 /proc/self/net/dev | awk -F: '{gsub(/ /, "", $1); print $1}' | xargs)
	[ "$ifaces" = "lo" ] || die "refusing to run: network interfaces '$ifaces' visible, PrivateNetwork is not in effect"
	shared=$(shared_dbus_names)
	[ -z "$shared" ] || die "refusing to run: on the session bus: $shared"
	exec "$@"
}

# ExecStopPost of dankcal-dev: runs after every dev process is gone, whatever stopped it. systemd
# logs that it can't set up the private network for it; it needs none.
cmd_on_stop() {
	trap 'systemctl --user --no-block start "$LIVE"' EXIT
	sha256sum "$REAL_DATA"/dankcal.db* >"$ROOT/real-after.sha256"
	rm -rf "$ROOT/after"
	mkdir -p "$ROOT/after"
	cp -p "$REAL_DATA"/dankcal.db* "$ROOT/after/"
}

cmd_ipc() {
	local sock
	sock=$(dev_socket) # never fall through to dcal's own lookup, which finds the live daemon
	DANKCAL_SOCKET=$sock exec "$ROOT/bin/dcal" ipc "$@"
}

# Hyprland only. grim captures the screen, so check the dev window is on a workspace a monitor
# shows (ui.show brings it up; this compositor keeps it on a special workspace) and crop to it.
cmd_screenshot() {
	local png=${1:-} pid qs win shown
	case "$png" in /*.png) ;; *) die "usage: dev-instance.sh screenshot <absolute path>.png" ;; esac
	command -v hyprctl >/dev/null || die "hyprctl not found: this needs Hyprland"
	pid=$(dev_pid)
	[ "$pid" -gt 0 ] || die "$UNIT is not running"
	qs=$(pgrep -n -P "$pid" -x qs) || die "no qs child of the dev daemon (pid $pid)"
	"$0" ipc ui.show >/dev/null
	sleep 1
	win=$(hyprctl clients -j | jq -c --argjson p "$qs" \
		'[.[] | select(.pid == $p and .mapped and (.hidden | not))] | max_by(.size[0] * .size[1]) // empty')
	[ -n "$win" ] || die "no mapped window for the dev qs (pid $qs)"
	shown=$(hyprctl monitors -j | jq --argjson w "$(jq '.workspace.id' <<<"$win")" \
		'any(.[]; .activeWorkspace.id == $w or .specialWorkspace.id == $w)')
	[ "$shown" = true ] ||
		die "the dev window is on workspace $(jq -r '.workspace.name' <<<"$win"), which no monitor shows; bring it up and rerun"
	grim -g "$(jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' <<<"$win")" "$png"
	echo "captured $png: $(jq -r '"window \"\(.title)\" class \(.class) pid \(.pid) workspace \(.workspace.name) at \(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' <<<"$win")"
	echo "dev qs pid: $qs"
}

cmd_probe() {
	local pid
	command -v curl >/dev/null || die "curl not found; cannot probe"
	pid=$(dev_pid)
	[ "$pid" -gt 0 ] || die "$UNIT is not running"
	echo "net namespace: dev $(readlink "/proc/$pid/ns/net"), host $(readlink /proc/self/ns/net)"
	echo "dev interfaces: $(tail -n +3 "/proc/$pid/net/dev" | awk -F: '{gsub(/ /, "", $1); print $1}' | xargs)"
	# curl exit 6 (resolve), 7 (connect) and 28 (timeout) mean unreachable; anything else fails.
	nsenter -t "$pid" -U -n --preserve-credentials sh -c '
		for url in https://www.googleapis.com https://graph.microsoft.com http://1.1.1.1; do
			rc=0; curl -sS -m 5 -o /dev/null "$url" || rc=$?
			case $rc in 6|7|28) ;; *) echo "FAIL: curl $url exited $rc"; exit 1 ;; esac
		done
		echo "offline: no remote host reachable from the dev instance"'
}

cmd_status() {
	echo "$UNIT: $(systemctl --user is-active "$UNIT" || true) (pid $(dev_pid))"
	echo "$LIVE: $(systemctl --user is-active "$LIVE" || true)"
	[ ! -f "$ROOT/home/data/dankcal/dankcal.db" ] ||
		echo "dev DB copy: $(db_versions "$ROOT/home/data/dankcal/dankcal.db")"
}

cmd_stop() {
	local fail=0 pid shared state before="$ROOT/real-before.sha256" after="$ROOT/real-after.sha256"
	state=$(systemctl --user is-active "$UNIT" || true)
	# STOP_INV is the dev instance seen before waiting for the lock (unset on start's own
	# failure path). A different one running now was started meanwhile by someone else.
	if [ -n "${STOP_INV+set}" ] &&
		[ "$(systemctl --user show -p InvocationID --value "$UNIT" 2>/dev/null || true)" != "$STOP_INV" ]; then
		case "$state" in
		active | activating | reloading | deactivating)
			echo "a newer dev instance started meanwhile; left running (pid $(dev_pid)), $LIVE stays stopped"
			exit 0
			;;
		esac
	fi
	case "$state" in
	active | activating | reloading | deactivating) systemctl --user stop "$UNIT" ;;
	esac
	for _ in $(seq 1 30); do
		systemctl --user is-active --quiet "$LIVE" && break
		sleep 1
	done
	systemctl --user is-active --quiet "$LIVE" || systemctl --user start "$LIVE" || true

	echo "== real DB"
	if [ ! -e "$before" ] && [ ! -e "$after" ]; then
		echo "no dev run since the last clean stop: nothing to compare"
	elif [ -f "$before" ] && [ -f "$after" ]; then
		echo "before:" && cat "$before"
		echo "after:" && cat "$after"
		if cmp -s "$before" "$after"; then
			echo "real DB unchanged while dcal.service was stopped"
		else
			echo "FAIL: real DB changed"; fail=1
		fi
		if [ -f "$ROOT/after/dankcal.db" ]; then
			echo "real DB after: $(db_versions "$ROOT/after/dankcal.db")"
		else
			echo "FAIL: missing $ROOT/after/dankcal.db"; fail=1
		fi
	else
		echo "FAIL: only one of $before and $after exists"; fail=1
	fi

	echo "== session bus"
	shared=$(shared_dbus_names)
	if [ -n "$shared" ]; then
		echo "FAIL: on the session bus at stop, may have been shared with the dev instance: $shared"; fail=1
	else
		echo "none on the bus at stop: no Secret Service or Evolution Data Server"
	fi

	echo "== processes"
	pgrep -a dcal || true
	local checkout
	checkout=$(cat "$ROOT/checkout" 2>/dev/null || echo "$ROOT")
	local left="^($ROOT/bin/dcal|qs -p $checkout/quickshell)( |\$)"
	if pgrep -f -- "$left" >/dev/null; then
		echo "FAIL: still running the dev build or its QML (restart $LIVE if it is the parent):"
		pgrep -a -f -- "$left"
		fail=1
	fi
	# Only daemons: short-lived `dcal ipc`/`dcal show` clients may come and go.
	for pid in $(pgrep -f '^([^ ]*/)?dcal run( |$)' || true); do
		cgroup=$(cat "/proc/$pid/cgroup" 2>/dev/null) || continue
		case "$cgroup" in */"$LIVE") ;; *) echo "FAIL: dcal daemon pid $pid is outside $LIVE"; fail=1 ;; esac
	done
	echo "$UNIT: $(systemctl --user is-active "$UNIT" || true)"
	echo "$LIVE: $(systemctl --user is-active "$LIVE" || true)"
	systemctl --user is-active --quiet "$LIVE" || { echo "FAIL: $LIVE not active"; fail=1; }
	[ "$fail" -eq 0 ] || { echo "scratch copy kept for diagnosis: $ROOT/home, $ROOT/after"; exit 1; }
	# The copy holds the accounts' tokens and data. The .sha256 files are the run's evidence;
	# moving them marks the run as checked, so a repeat stop has nothing to compare.
	rm -rf "$ROOT/home" "$ROOT/after"
	mkdir -p "$ROOT/last-run"
	[ ! -e "$before" ] || mv -f "$before" "$after" "$ROOT/last-run/"
	echo "dev instance stopped cleanly (evidence in $ROOT/last-run)"
}

case "${1:-}" in
start)
	scratch_ok
	exec 9>"$LOCK"
	flock -n 9 || die "another dev-instance start or stop is running (lock $LOCK)"
	;;
stop) # waits out a peer's start (build included) rather than leaving dcal stopped
	scratch_ok
	STOP_INV=$(systemctl --user show -p InvocationID --value "$UNIT" 2>/dev/null || true)
	exec 9>"$LOCK"
	flock -w 180 9 || die "lock $LOCK still held after 180s"
	;;
esac

case "${1:-}" in
start) shift; cmd_start "$@" ;;
guard) shift; cmd_guard "$@" ;;
on-stop) cmd_on_stop ;;
ipc) shift; cmd_ipc "$@" ;;
screenshot) shift; cmd_screenshot "$@" ;;
probe) cmd_probe ;;
status) cmd_status ;;
stop) cmd_stop ;;
*) awk 'NR > 1 && /^# Isolation:/ { exit } NR > 1' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
