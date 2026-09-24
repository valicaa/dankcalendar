# Lessons

Corrections and mistakes from past sessions, as rules. Loaded into every session by the
SessionStart hook; apply them before acting. Add one whenever the user corrects you or you
catch your own mistake. Merge or drop rules that turn out wrong or duplicate.
Format: `- YYYY-MM-DD — <what went wrong> → <rule>`

- 2026-09-24 — Documented `graphify path <id>` and "`/graphify --update` refreshes QML" without running them; both were false → run every command exactly as written before putting it in CLAUDE.md or a skill.
- 2026-09-24 — Built a custom QML tool before checking whether graphify supports QML; the user had to ask → before writing custom tooling, check the tool's options, docs and open issues, and say what you found.
- 2026-09-24 — graphify's fuzzy dedup merged `system.autostart.get` into `.set` during a merge → never let fuzzy dedup touch deterministic ids; diff node sets before/after any graph write.
- 2026-09-24 — Measured "no Repo method has a caller outside core/repo" but wrote "no Repo method has a caller" → write the exact claim you measured, with its filter.
- 2026-09-24 — `graph-calls.py` skipped nodes without edges, so its grep fallback never ran for the case it was built for → test a tool on the exact case that motivated it.
- 2026-09-24 — `graphify install` silently rewrote a line in `~/.claude/CLAUDE.md` → back up and diff config files before running any installer.
- 2026-09-24 — A context-free reviewer found 12 real problems in docs I had already "verified" → after writing docs or tools, have a fresh subagent follow them literally before reporting done.
- 2026-09-24 — The main session wrote and tested tooling itself instead of delegating, filling its context with file dumps → the main session is the PM (`project-manager` skill): it delegates all technical work to the `.claude/agents/` roster and verifies the evidence in their reports.
- 2026-09-24 — Builder exempted `claude/*` as the worktree branch prefix from a binary string; real agent worktrees are `worktree-agent-<id>` → prove naming/format assumptions by creating the real thing, not by grepping for strings.
- 2026-09-24 — `gh`'s default repo was upstream AvengeMedia while docs had bare `gh issue` commands → every `gh` command in docs and hook messages carries an explicit `-R`; never rely on `gh repo set-default`.
