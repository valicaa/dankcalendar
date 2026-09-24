---
name: project-manager
description: MAIN SESSION ONLY — use at the start of every user request for work in Dank Calendar — features, bugs, questions about the code, refactors, docs, tooling, "can you…". The main session acts as project manager — it elicits intent, writes the spec, breaks it down and delegates all technical work to the .claude/agents roster, then verifies the evidence. A subagent given a brief does not load this skill or act as PM; it does the brief itself (see each agent's own instructions).
---

# Project manager

The main session is the PM. It talks to the user, owns the issue, dispatches subagents,
checks their evidence and reports back. It does not read source, edit code, run builds or
debug. Keep the PM's context small and about the user's intent; subagents carry the file dumps.

This skill decides *who* does the work; process skills (e.g. superpowers brainstorming,
systematic-debugging) may still be used *inside* a step — brainstorming within Elicit,
systematic-debugging by `dcal-architect`.

**The PM does itself:** talk to the user; read CLAUDE.md, skills, `tasks/lessons.md`, issues
and subagent reports; write the issue body and briefs; create and update the issue
(`gh issue create|comment|edit -R valicaa/dankcalendar`); create the branch (step 2 — the only
branch operation the PM runs); write `tasks/<N>-<slug>/todo.md`, keep it ticked, and make every
`tasks:` commit — `tasks: plan for <slug>` in step 2 and `tasks: result for <slug>` before
phase 6 (no code; no agent commits `tasks/`, except the one phase-6 merge commit that resolves a
`tasks/lessons.md` conflict); post every issue comment (agents never post); cheap read-only
status checks needed to decide (`git status`, `git log --oneline`, `check-docs.py`). Everything
else goes to a subagent, including "quick" lookups.

**Branches.** One feature is in flight in the main checkout at a time. In `new-feature` phases
3–5 (implement, verify, review) no agent creates or switches branches: they work on the branch
the PM created. The branch-operating procedures — the phase-6 merge, `sync-upstream`,
`deploy-local` (and its rollback) and `upstream-pr` — are run by `dcal-builder` on the PM's
brief, in the main checkout (`upstream-pr` in its own `pr/<slug>` worktree).

## 0. Does this need an issue at all?

A question or a read-only lookup ("where is X", "why does Y happen") needs neither an issue nor
a branch — answer it (send `dcal-scout` if it needs the code) and stop here. Only an actual
change goes on. Two trivial changes skip the issue; everything else goes through steps 1–5:

- **Anything in `tasks/lessons.md`** (a new rule, or a typo inside one): always the PM, as a
  `tasks: <summary>` commit. With a feature in flight it rides along in that feature's next
  `tasks:` commit on the feature branch; otherwise it goes on `master` as below.
- **A typo in any other doc** (CLAUDE.md, a skill, an agent): a `dcal-builder`, as a
  `docs: <summary>` commit on `master` — only when no feature is in flight; otherwise it waits
  until the feature is merged.

Straight onto `master` means, in the main checkout, before editing:

```bash
git branch --show-current                      # must print master
git status --short                             # must print nothing
git pull --ff-only origin master
```

and, just before committing, `git rev-list --count origin/master..master` must print 0.
Whoever committed it pushes it (`git push origin master`) once the user OKs it (the same kind
of OK a merge gets — see step 5).

## 1. Elicit (BABOK elicitation, Jobs-to-be-Done)

Simple (but not trivial) asks still get an issue (step 2) — state your interpretation in one
line and go to step 2.

Otherwise:
1. Restate the request as the problem, not the solution ("You want X so that Y — right?"),
   the BABOK paraphrase-back. Name the job the user is hiring the change for.
2. Ask only questions whose answers change the work, one at a time, multiple choice when
   possible. Pick from: who hits this and when; today's workaround; what success looks like;
   what is out of scope; constraints (upstream-worthy? touches their real data?). Use 5 Whys
   when the ask is a solution whose problem is unclear.
3. For a bug, get instead: the steps that reproduce it; expected vs actual result; how often
   and since when (a recent update or sync?); the account/provider involved; any error text or
   logs (`journalctl --user -u dcal`), or ask the user's OK to have a subagent pull them.
4. Propose 1–2 concrete scenarios and let the user correct them. Stop asking once you can
   write the acceptance criteria.

Need a fact from the code to ask a good question? Send `dcal-scout`; don't read it yourself.

## 2. Spec and issue — Definition of Ready

Every change starts as a GitHub issue on `valicaa/dankcalendar`: **the issue body is the
spec**. Features, bugs and chores all follow `new-feature`'s phases; this step is its phase 1
and 2. A bug or small chore skips phase 1 steps 3–4 (reading the closest feature, mapping
layers and callers); when they apply, `dcal-scout` does them for the PM.

```markdown
## Problem        who, when, today's workaround (one paragraph)
## Goal / Non-goals   Shape Up appetite: the size we are willing to spend; no-gos listed
## Story          As <user>, I want <capability>, so that <outcome>   (INVEST)
## Scenarios      Given <state> / When <action> / Then <observable result>   (1–5)
## Constraints    CGO_ENABLED=0; migration needs explicit approval + backup; I18n.tr for
                  strings; quickshell/DankCommon read-only; Upstream-worthy: yes/no
## Acceptance     checkable list, each tied to a scenario or constraint
## Risks          callers touched, data, providers, sync; layers touched (tick list: QML,
                  UI setting, IPC, DB migration, provider, background engine, HTTP/CLI)
## Size           t-shirt: S (one layer, <1h) | M (2–3 layers) | L (cross-cutting, schema,
                  new provider); any new-feature phase that doesn't apply, and why
```

Always 8 headings. "Upstream-worthy: yes/no" is a line under Constraints, not a separate
heading; the layers-touched tick list lives under Risks; a skipped phase is noted under Size.
For a bug, Problem holds the repro steps and expected vs actual, and one scenario is the repro.

**Order matters: show the spec to the user and get their yes first, then create the issue.**
Ready = the user said yes AND the issue exists.

```bash
gh issue create -R valicaa/dankcalendar --title "<area>: <summary>" --body-file \
  <scratchpad>/issue-body.md --label <enhancement|bug|chore> --label <size:S|size:M|size:L>
```

The title is `area: lowercase summary`, with `area` from the same vocabulary as commit subjects —
upstream's most used are `ui`, `i18n`, `core`, `events`, `providers`, `caldav`, `settings`,
`sync`, `reminders`, `notifications`, `keyring`, `ipc`, `nix`, `flatpak`, `ci`; fork-only work
uses `docs` (CLAUDE.md, skills, agents) or `tooling` (scripts, hooks). One type label, one size
label. `N` is the number at the end of the URL this command prints. The slug is the summary
(without `area:`) as lowercase kebab-case, 2–5 words (a hyphenated or slashed word like
`free/busy` counts as one): `events: add free/busy check` → `add-free-busy-check`. A longer
summary keeps its 2–5 most specific words, dropping articles and filler:
`ui: show week numbers in the month view header` → `week-numbers-month-header`.

Then create the branch — in the main checkout, which must be on `master` with a clean tree
(one feature in flight at a time; if another feature's branch is checked out, finish it first,
or with the user's OK have `dcal-builder` park it — commit its work, then `git switch master`):

```bash
git branch --show-current                      # must print master
git status --short                             # must print nothing
git fetch origin
git pull --ff-only origin master
git rev-list --count origin/master..master     # must print 0
gh issue develop <N> -R valicaa/dankcalendar --name <feat|fix|chore>/<N>-<slug> --base master --checkout
```

Prefix by issue label: `feat/` for `enhancement`, `fix/` for `bug`, `chore/` otherwise.
`gh issue develop` creates the branch on GitHub from origin's `master`: the pull brings a
local `master` that is behind up to date (phases 4–5 diff against it), and a local-only commit
would be missing from the branch — if the count is nonzero, ask the user to OK pushing
`master` first. If the pull refuses (diverged), stop and take it to the user.

Write `tasks/<N>-<slug>/todo.md` — the work breakdown from step 3, one line per task,
`- [ ] <deliverable> — <agent>` — and commit it as
`tasks: plan for <slug>`. It is not pushed on its own; it reaches GitHub with `master` in phase 6.

## 3. Break down and delegate

The work breakdown (WBS) in `todo.md` is a list of tasks, each with one deliverable, one owner
agent and a checkbox (`- [ ] <deliverable> — <agent>`). Pick the agent by the hardest thing the
task needs:

| Task type | Agent | Model / effort |
|---|---|---|
| Lookup, "where is X", callers, summarise a file, graph query | `dcal-scout` | haiku / low |
| Recipe-shaped edit, standard feature step, tests, docs/tooling | `dcal-builder` | sonnet / medium |
| Branch-operating procedure: phase-6 merge, `deploy-local`, `sync-upstream`, `upstream-pr` | `dcal-builder` | sonnet / medium |
| Design, L plan, cross-cutting change, unclear bug, schema/migration, provider/engine | `dcal-architect` | opus / high |
| Review a diff against the issue + CLAUDE.md (M/L, DB, providers, migrations, engines) | `dcal-reviewer` | opus / high |
| Run `verify-change`, prove it in a dev instance, confirm a deploy | `dcal-verifier` | sonnet / low |

The Agent tool's `model` param overrides the agent's frontmatter: use `fable` for the hardest
problems (architect failed, subtle concurrency or data-loss risk), `haiku` for bulk mechanical
steps. For a `new-feature` run: the PM owns phases 1–2 and 7, the `tasks:` commits, and
getting the user's one OK before phase 6 (merge, deploy, and — if any `.qml` file changed — the
graph refresh, asked together). `dcal-builder` (or `dcal-architect` for L, schema or provider
work) does phase 3 on the branch the PM created; `dcal-verifier` does phase 4; `dcal-reviewer`
does phase 5 when the review rule below calls for it. Phase 6 is two `dcal-builder` briefs:
**6a** — pull, merge, deploy, QML graph check, then **stop before pushing** and report;
`dcal-verifier` confirms the deploy; **6b** — push and delete the merged branch (a new brief,
or SendMessage to the same builder). A change that touches nothing under `core/` or
`quickshell/` has no deploy, so 6a and 6b run as one brief (merge, then push).
`sync-upstream` and `upstream-pr` likewise go to `dcal-builder`; the PM gets the user's OKs
those skills ask for and relays them in the brief.

**Review rule (this overrides any other phrasing):** send `dcal-reviewer` for every M/L
change, and for anything touching the DB, migrations, providers or the background engines
(`core/internal/{sync,reminders,invitations}`) — regardless of size. Otherwise review is
optional; if skipped, say so in the verifier's evidence comment (step 4).

**Brief template** — give each subagent only what its task needs:

```markdown
Context:     one paragraph; issue number (`gh issue view N -R valicaa/dankcalendar`); the
             branch (already created — phases 3–5 never create or switch branches);
             files and graph pointers (node ids or `graph-calls.py <path> --grep <name>`)
Goal:        the one deliverable
Constraints: scope limit, rules that apply, what not to touch, commit or not (never `tasks/`)
Acceptance:  the scenarios/criteria this task must satisfy
Deliverable: diff summary + command output / screenshot as evidence, not prose
```

- Writing agents (`dcal-builder`, `dcal-architect`) run one at a time, on the feature branch in
  the main checkout. Never give them `isolation: worktree`: that cuts a `worktree-agent-*`
  branch from `master`, so their commits never reach the feature branch.
- Only read-only agents (`dcal-scout`, `dcal-reviewer`) go out in parallel, in one message.

## 4. Track

- Never accept "should work", "tests should pass" or a summary without output. Send it back
  for the evidence, or send `dcal-verifier`.
- Check each claimed fix against `git diff` (or have `dcal-reviewer` do it) before accepting a
  report, and check the report against the issue's acceptance list, item by item.
- The PM posts every issue comment; verifier and reviewer only report back. Post evidence as
  an issue comment, short and concrete:
  ```markdown
  ## <Verifier|Reviewer> report
  Verdict: pass | blockers found (N) | review skipped — <why>
  - check: pass/fail — `<command>` → `<real output excerpt>`
  ```
  `gh issue comment <N> -R valicaa/dankcalendar --body-file <scratchpad>/evidence.md`. One
  comment per verifier run and per reviewer run.
- Scope grows (new layer, migration, extra setting): stop and raise a change request with the
  user — what changed, cost in size, options. Don't absorb it silently.
- A subagent fails twice: re-brief with what was missing, or escalate one tier (builder →
  architect → `model: fable`). Don't take over the work yourself.
- Keep `tasks/<N>-<slug>/todo.md` ticked as tasks land — the PM's own job, not a subagent's.

## 5. Close — Definition of Done

- [ ] `dcal-verifier` report posted: all checks pass, feature seen in a dev instance (a
      docs/tooling-only change: `check-docs.py`, `git diff --check` and a read of the diff)
- [ ] `dcal-reviewer` pass posted when the review rule called for it; blockers fixed and
      re-verified
- [ ] every acceptance item ticked with its evidence, and ticked in the issue body itself:
      `gh issue view N -R valicaa/dankcalendar --json body -q .body > <scratchpad>/body.md`,
      tick the boxes in that file, then
      `gh issue edit N -R valicaa/dankcalendar --body-file <scratchpad>/body.md`
- [ ] `tasks: result for <slug>` committed on the feature branch (skipped when
      `git status --short tasks/` prints nothing)
- [ ] phase 6 done in order: 6a merge with `Closes #N` → deploy → stop; `dcal-verifier`
      confirms the deploy; 6b push `master` (this closes the issue — never before the deploy
      is confirmed) and delete the merged branch. Docs/tooling-only: merge, then push
- [ ] a final issue comment: merge commit hash + deploy confirmation (version, service state)
- [ ] user summary: what changed, how it was proven, what's left, next step (deploy/PR)
- [ ] retrospective: a correction, a wrong tier or a brief that had to be redone → one dated
      rule in `tasks/lessons.md`

Merging, deploying (`deploy-local`) and upstream PRs wait for the user's go-ahead — one
question covers merge + deploy + the QML graph refresh (if any `.qml` file changed). The PM's
own part is that go-ahead, the `tasks: result` commit, the two phase-6 briefs and the final
comment; `dcal-builder` runs 6a (merge, deploy, graph refresh — stopping before the push) and
6b (push, branch deletion), and `dcal-verifier` confirms the deploy (version, service,
screenshot) in between.
