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
(`gh issue create|comment|edit|reopen -R valicaa/dankcalendar`); create the branch (step 2, or a
step-0 `docs/<slug>` branch — the only branch operations the PM runs); write
`tasks/<N>-<slug>/todo.md`, keep it ticked, and make every `tasks:` commit —
`tasks: plan for <slug>` in step 2 and `tasks: result for <slug>` in `new-feature` 6.1 (no code;
no agent commits `tasks/`, except phase 6's merge of `origin/master` that resolves a
`tasks/lessons.md` conflict); write PR bodies; post every issue and PR comment (agents never
post); cheap read-only status checks needed to decide (`git status`, `git log --oneline`,
`check-docs.py`, `gh pr view`). Everything else goes to a subagent, including "quick" lookups.

**Branches.** One feature is in flight at a time, from its branch's creation until `new-feature`
6.4 is done or its PR is closed. In phases 3–5 no agent creates or switches branches: they work
on the branch the PM created. The branch-operating procedures — phase 6, step 0's trivial PR,
`sync-upstream`, `deploy-local` (and its rollback) and `upstream-pr` — are run by `dcal-builder`
on the PM's brief, in the main checkout (`upstream-pr` in its own `pr/<slug>` worktree).
`master` moves only when the owner merges a PR on GitHub: nobody commits on it (the check-docs
hook blocks it) or pushes it, and the main checkout returns to it whenever a PR is open.

## 0. Does this need an issue at all?

A question or a read-only lookup ("where is X", "why does Y happen") needs neither an issue nor
a branch — answer it (send `dcal-scout` if it needs the code) and stop here. Only an actual
change goes on. Two trivial changes skip the issue, but not the PR — every change reaches
`master` as a PR the owner merges; everything else goes through steps 1–5:

- **Anything in `tasks/lessons.md`** (a new rule, or a typo inside one): always the PM, as a
  `tasks: <summary>` commit. While a feature branch is checked out (phases 2–5) it rides along
  in that feature's next `tasks:` commit; otherwise it goes on a trivial branch as below.
- **A typo in any other doc** (CLAUDE.md, a skill, an agent): a `dcal-builder`, as a
  `docs: <summary>` commit on a trivial branch — only while the main checkout is on `master`;
  otherwise it waits until that feature's PR is open.

A trivial branch is `docs/<slug>` (no issue; the check-docs hook takes commits on it only while
every uncommitted path passes `verify-change` section 0's docs-only test), made by the committer:

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git pull --ff-only origin master
git switch -c docs/<slug> || exit 1
```

Then `dcal-builder` runs `new-feature` 6.2 with `<branch>` = `docs/<slug>`, except that the PR
takes the commit subject as title and a PM-written body with no `Closes` (what, why, attribution):

```bash
gh pr create -R valicaa/dankcalendar --base master --head docs/<slug> --title "$(git log -1 --format=%s docs/<slug>)" --body-file <scratchpad>/pr-docs-<slug>.md
```

The PM gives the owner the link. Once merged, `dcal-builder` runs 6.4's first block; docs-only,
so nothing is deployed.

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
(one feature in flight — see Branches; with the user's OK a checked-out feature can be parked:
`dcal-builder` commits its work, then `git switch master`):

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
would be missing from the branch. `master` never holds local commits, so a nonzero count or a
refused pull (diverged) means something went wrong: stop and take it to the user.

Write `tasks/<N>-<slug>/todo.md` — the work breakdown from step 3, one line per task,
`- [ ] <deliverable> — <agent>` — and commit it as
`tasks: plan for <slug>`. It is not pushed on its own; phase 6 pushes it with the branch.

## 3. Break down and delegate

The work breakdown (WBS) in `todo.md` is a list of tasks, each with one deliverable, one owner
agent and a checkbox (`- [ ] <deliverable> — <agent>`). Pick the agent by the hardest thing the
task needs:

| Task type | Agent | Model / effort |
|---|---|---|
| Lookup, "where is X", callers, summarise a file, graph query | `dcal-scout` | haiku / low |
| Recipe-shaped edit, standard feature step, tests, docs/tooling | `dcal-builder` | sonnet / medium |
| Branch-operating procedure: phase-6 PR and post-merge, `deploy-local`, `sync-upstream`, `upstream-pr` | `dcal-builder` | sonnet / medium |
| Design, L plan, cross-cutting change, unclear bug, schema/migration, provider/engine | `dcal-architect` | opus / high |
| Review a diff against the issue + CLAUDE.md (M/L, DB, providers, migrations, engines) | `dcal-reviewer` | opus / high |
| Run `verify-change`, prove it in a dev instance, confirm a deploy | `dcal-verifier` | sonnet / low |

The Agent tool's `model` param overrides the agent's frontmatter: use `fable` for the hardest
problems (architect failed, subtle concurrency or data-loss risk), `haiku` for bulk mechanical
steps. For a `new-feature` run: the PM owns phases 1–2 and 7, the `tasks:` commits and the PR
body. `dcal-builder` (or `dcal-architect` for L, schema or provider work) does phase 3 on the
branch the PM created; `dcal-verifier` does phase 4; `dcal-reviewer` does phase 5 when the review
rule below calls for it. Phase 6 is two `dcal-builder` briefs around the owner's merge on
GitHub: **6.2** push, open the PR, back to `master`; **6.4** pull, delete the branch, deploy
unless docs-only, then `dcal-verifier` confirms. `sync-upstream` (which also ends in a PR) and
`upstream-pr` go to `dcal-builder`; the PM relays any OK those skills ask the user for.

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
      docs-only change per `verify-change` section 0: `check-docs.py`, `git diff --check` and
      a read of the diff)
- [ ] `dcal-reviewer` pass posted when the review rule called for it; blockers fixed and
      re-verified
- [ ] every acceptance item ticked with its evidence, and ticked in the issue body itself:
      `gh issue view N -R valicaa/dankcalendar --json body -q .body > <scratchpad>/body.md`,
      tick the boxes in that file, then
      `gh issue edit N -R valicaa/dankcalendar --body-file <scratchpad>/body.md`
- [ ] retrospective: a correction, a wrong tier or a brief that had to be redone → one dated
      rule in `tasks/lessons.md`, in the `tasks: result` commit (a later one: step 0)
- [ ] `tasks: result for <slug>` committed on the feature branch (skipped when
      `git status --short tasks/` prints nothing)
- [ ] PR open on `valicaa/dankcalendar` (body: `Closes #N` first, evidence comment links,
      attribution last), its URL posted on the issue, main checkout back on an up-to-date
      `master`
- [ ] user summary: what changed, how it was proven, the PR link, what's left — no merge
      question
- [ ] after the owner merges (the merge closes the issue): pulled, local branch deleted,
      deployed unless docs-only and confirmed by `dcal-verifier`; a final issue comment with
      the merge commit hash + deploy confirmation (version, service state) or "docs-only". A
      failed deploy: rollback, reopen, new PR (`new-feature` phase 6)

The PM never asks for a merge, push or deploy OK in chat: the owner merges the PR on GitHub, and
that is the OK to deploy (the PM learns of it from the owner or
`gh pr view <PR> -R valicaa/dankcalendar --json state,mergeCommit`). Only the QML graph refresh
(LLM cost) and `upstream-pr` still wait for the user's word.
