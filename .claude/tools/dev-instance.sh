#!/usr/bin/env bash
# Offline dev instance of Dank Calendar on a scratch copy of the real data.
#
#   dev-instance.sh start <checkout>   build <checkout>/core, stop dcal.service, copy the real
#                                      data, run the build as the transient unit dankcal-dev
#   dev-instance.sh ipc <method> [k=v…]  `dcal ipc` against the dev instance only
#   dev-instance.sh probe              try to reach the internet from inside the dev instance's
#                                      network namespace (must fail)
#   dev-instance.sh status             state of dankcal-dev and dcal, versions of the dev DB copy
#   dev-instance.sh stop               stop dankcal-dev, check the real DB is unchanged, no dev
#                                      process is left and dcal.service is active again;
#                                      exits 1 unless it prints "dev instance stopped cleanly"
#
# <checkout> is the absolute path of any checkout of this repo (the main one or a linked
# worktree with its submodule initialised). Its QML runs from <checkout>/quickshell.
#
# Isolation:
#   data     XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_STATE_HOME point under $ROOT/home, seeded by
#            copying the real dankcal dirs while dcal.service is stopped. The real dirs are
#            only read (cp, sha256sum); sqlite3 only ever opens the copies.
#   offline  the unit runs with PrivateNetwork=yes: its only interface is loopback. systemd
#            silently runs a unit without it when the namespace can't be set up, so `guard`
#            execs dcal only after checking loopback is the only interface it can see. `probe`
#            shows it from inside. The copied keyring keeps the accounts' tokens, so providers
#            fail as offline, never as signed out.
#   process  dankcal-dev Conflicts= dcal.service, and After= orders the stop of one before the
#            start of the other, so the two never run together (a live dcal started next to
#            the dev one takes its QML dir from $XDG_RUNTIME_DIR/dankcal.path). Stopping the
#            unit kills its whole cgroup (daemon and qs); its ExecStopPost records the real
#            DB's checksum and starts dcal.service again, also when the dev instance crashes
#            or hits RuntimeMaxSec.
set -euo pipefail

ROOT="/tmp/claude-$(id -u)/dankcal-dev"
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

cmd_start() {
	local checkout=${1:-}
	[ -n "$checkout" ] || die "usage: dev-instance.sh start <absolute checkout path>"
	case "$checkout" in /*) ;; *) die "checkout path must be absolute: $checkout" ;; esac
	checkout=${checkout%/}
	[ "$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null)" = "$checkout" ] ||
		die "$checkout is not the top of a git checkout"
	[ -d "$checkout/core/cmd/dcal" ] || die "$checkout has no core/cmd/dcal"
	[ -f "$checkout/quickshell/DankCommon/Widgets/DankIcon.qml" ] ||
		die "DankCommon missing: git -C $checkout submodule update --init"
	! systemctl --user is-active --quiet "$UNIT" || die "$UNIT already running; stop it first"
	[ "$ROOT" = "/tmp/claude-$(id -u)/dankcal-dev" ] || die "unexpected ROOT $ROOT"
	# A Secret Service would hand the dev daemon the real credentials over D-Bus (outside the
	# scratch copy, and writable); today the keyring is the file store in the data dir.
	if busctl --user list --no-legend 2>/dev/null | awk '{print $1}' | grep -qx org.freedesktop.secrets; then
		die "org.freedesktop.secrets is on the session bus; the dev instance would share real credentials"
	fi

	echo "== build $checkout"
	mkdir -p "$ROOT/bin"
	(cd "$checkout/core" && CGO_ENABLED=0 go build -o "$ROOT/bin/dcal" ./cmd/dcal)
	install -m 0755 "$(readlink -f "$0")" "$ROOT/bin/dev-instance.sh"
	echo "$checkout" >"$ROOT/checkout"

	echo "== stop $LIVE and copy the real data"
	systemctl --user stop "$LIVE"
	# Until the unit exists (its ExecStopPost takes over), any failure restarts the live one.
	trap 'systemctl --user start "$LIVE"' EXIT
	rm -rf "$ROOT/home" "$ROOT/after" "$ROOT/real-before.sha256" "$ROOT/real-after.sha256"
	mkdir -p "$ROOT/home/data" "$ROOT/home/config" "$ROOT/home/state"
	sha256sum "$REAL_DATA"/dankcal.db* >"$ROOT/real-before.sha256"
	cp -a "$REAL_DATA" "$ROOT/home/data/"
	[ ! -d "$REAL_CONFIG" ] || cp -a "$REAL_CONFIG" "$ROOT/home/config/"
	[ ! -d "$REAL_STATE" ] || cp -a "$REAL_STATE" "$ROOT/home/state/"
	cat "$ROOT/real-before.sha256"
	echo "real DB before: $(db_versions "$ROOT/home/data/dankcal/dankcal.db")"

	echo "== start $UNIT"
	systemd-run --user --unit="$UNIT" --collect --quiet \
		-p PrivateNetwork=yes \
		-p Conflicts="$LIVE" -p After="$LIVE" \
		-p RuntimeMaxSec="$MAX_RUNTIME" \
		-p ExecStopPost="$ROOT/bin/dev-instance.sh on-stop" \
		-E XDG_DATA_HOME="$ROOT/home/data" \
		-E XDG_CONFIG_HOME="$ROOT/home/config" \
		-E XDG_STATE_HOME="$ROOT/home/state" \
		-E DANKCAL_DB_PATH="$ROOT/home/data/dankcal/dankcal.db" \
		-E DCAL_ENABLE_HOTRELOAD=1 \
		"$ROOT/bin/dev-instance.sh" guard "$ROOT/bin/dcal" run -c "$checkout/quickshell"
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

# ExecStart wrapper of dankcal-dev: refuse to run dcal with any network but loopback.
cmd_guard() {
	local ifaces
	ifaces=$(tail -n +3 /proc/self/net/dev | awk -F: '{gsub(/ /, "", $1); print $1}' | xargs)
	[ "$ifaces" = "lo" ] || die "refusing to run: network interfaces '$ifaces' visible, PrivateNetwork is not in effect"
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

cmd_probe() {
	local pid
	pid=$(dev_pid)
	[ "$pid" -gt 0 ] || die "$UNIT is not running"
	echo "net namespace: dev $(readlink "/proc/$pid/ns/net"), host $(readlink /proc/self/ns/net)"
	echo "dev interfaces: $(tail -n +3 "/proc/$pid/net/dev" | awk -F: '{gsub(/ /, "", $1); print $1}' | xargs)"
	nsenter -t "$pid" -U -n --preserve-credentials sh -c '
		for url in https://www.googleapis.com https://graph.microsoft.com http://1.1.1.1; do
			if curl -sS -m 5 -o /dev/null "$url"; then echo "REACHED $url"; exit 1; fi
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
	local fail=0 pid
	if systemctl --user is-active --quiet "$UNIT"; then
		systemctl --user stop "$UNIT"
	fi
	for _ in $(seq 1 30); do
		systemctl --user is-active --quiet "$LIVE" && break
		sleep 1
	done
	systemctl --user is-active --quiet "$LIVE" || systemctl --user start "$LIVE" || true

	# The copied tokens are only needed while the dev instance runs.
	rm -rf "$ROOT/home/data/dankcal/keyring"

	echo "== real DB"
	if [ -f "$ROOT/real-before.sha256" ] && [ -f "$ROOT/real-after.sha256" ]; then
		echo "before:" && cat "$ROOT/real-before.sha256"
		echo "after:" && cat "$ROOT/real-after.sha256"
		if cmp -s "$ROOT/real-before.sha256" "$ROOT/real-after.sha256"; then
			echo "real DB unchanged while dcal.service was stopped"
		else
			echo "FAIL: real DB changed"; fail=1
		fi
		echo "real DB after: $(db_versions "$ROOT/after/dankcal.db")"
	else
		echo "FAIL: missing $ROOT/real-before.sha256 or real-after.sha256"; fail=1
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
	for pid in $(pgrep -x dcal || true); do
		grep -q "/$LIVE\$" "/proc/$pid/cgroup" || { echo "FAIL: dcal pid $pid is outside $LIVE"; fail=1; }
	done
	echo "$UNIT: $(systemctl --user is-active "$UNIT" || true)"
	echo "$LIVE: $(systemctl --user is-active "$LIVE" || true)"
	systemctl --user is-active --quiet "$LIVE" || { echo "FAIL: $LIVE not active"; fail=1; }
	[ "$fail" -eq 0 ] && echo "dev instance stopped cleanly" || exit 1
}

case "${1:-}" in
start) shift; cmd_start "$@" ;;
guard) shift; cmd_guard "$@" ;;
on-stop) cmd_on_stop ;;
ipc) shift; cmd_ipc "$@" ;;
probe) cmd_probe ;;
status) cmd_status ;;
stop) cmd_stop ;;
*) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
