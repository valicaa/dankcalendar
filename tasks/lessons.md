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
- 2026-09-24 — Moved upstream-pr into a worktree with `cd ../wt` then relative commands; a subagent's cwd and shell variables both reset between Bash calls → any procedure that works in another directory writes the literal absolute path into every command (`git -C /abs/wt …` or `cd /abs/wt && …`), each block self-contained; never a `$W` set in an earlier call.
- 2026-09-24 — `git log --grep "Closes #7"` matched "Closes #70" → anchor any grep for a number (`-E '^Closes #7$'`).
- 2026-09-24 — Two reviews passed the skills as consistent, but a literal walkthrough found owner and order contradictions → run the fresh-agent walkthrough in the same round as the first review, not after.
- 2026-09-24 — A builder's round reports twice claimed fixes that `git diff` didn't contain → check every claimed fix against the diff (or have the reviewer do it) before accepting a report; after two false reports escalate a tier.
- 2026-09-24 — Guarded shell blocks only against unset variables; an empty or wrong substituted path still let `rm -rf` run in $HOME → any destructive block first asserts it is in the expected repo/branch (`git rev-parse --show-toplevel`, `git branch --show-current`) with `|| exit 1`, and uses git commands over bare `rm -rf`.
- 2026-09-25 — Switched the main checkout to a new branch 3 s after another session had checked out its own branch there; its commit landed on mine → before any branch switch in the main checkout, run `git reflog -3 --date=relative` and stop if another session switched or committed in the last few minutes; parallel sessions need separate checkouts.
- 2026-09-25 — Each fix round on write-issue added a rule and broke another place that states it (size rule vs dropdown vs checklist vs worked example), so it took five rounds → a fix brief for a doc names every place the same rule appears (sections, forms, examples, other skills) and requires one wording in all of them; state a rule once and point to it rather than restating.
- 2026-09-25 — Another Claude session started issue #16 in the same main checkout 3s after I branched for #14; my `tasks:` commit landed on its branch, and my builder switched the checkout back from under it → before creating a branch, run `ListAgents` and stop if a peer session is working in this repo; every commit block asserts `git branch --show-current` first; a brief says "if the checkout is not on <branch>, stop and report — never switch".
