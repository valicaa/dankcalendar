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
(`gh issue create|comment|edit -R valicaa/dankcalendar`); create the branch
(`git fetch origin`, `gh issue develop … --checkout`); write `tasks/<N>-<slug>/todo.md` and
commit it, and keep it ticked as tasks land (`tasks:` commits only — no code); cheap read-only
status checks needed to decide (`git status`, `git log --oneline`, `check-docs.py`). Builders,
architects, verifiers and reviewers only ever work on a branch the PM has already created; they
never create or switch branches. Everything past that goes to a subagent, including "quick"
lookups.

## 0. Does this need an issue at all?

A question or a read-only lookup ("where is X", "why does Y happen") needs neither an issue nor
a branch — answer it (send `dcal-scout` if it needs the code) and stop here. Only an actual
change goes on. A trivial change — a typo, one `tasks/lessons.md` line — also skips the issue:
commit it straight on `master` as `tasks:`/`docs: <summary>`, and get the user's OK to push it
(the same kind of OK a merge gets — see step 5). Everything else goes through steps 1–5.

## 1. Elicit (BABOK elicitation, Jobs-to-be-Done)

Trivial or unambiguous asks still get an issue (step 2) — state your interpretation in one
line and go to step 2.

Otherwise:
1. Restate the request as the problem, not the solution ("You want X so that Y — right?"),
   the BABOK paraphrase-back. Name the job the user is hiring the change for.
2. Ask only questions whose answers change the work, one at a time, multiple choice when
   possible. Pick from: who hits this and when; today's workaround; what success looks like;
   what is out of scope; constraints (upstream-worthy? touches their real data?). Use 5 Whys
   when the ask is a solution whose problem is unclear.
3. Propose 1–2 concrete scenarios and let the user correct them. Stop asking once you can
   write the acceptance criteria.

Need a fact from the code to ask a good question? Send `dcal-scout`; don't read it yourself.

## 2. Spec and issue — Definition of Ready

Every change starts as a GitHub issue on `valicaa/dankcalendar`: **the issue body is the
spec**. This is `new-feature` phase 1 for a feature or behaviour change; a bug or small task
uses the same template and the same flow, just skipping phase 1's deeper code-mapping steps.

```markdown
## Problem        who, when, today's workaround (one paragraph)
## Goal / Non-goals   Shape Up appetite: the size we are willing to spend; no-gos listed
## Story          As <user>, I want <capability>, so that <outcome>   (INVEST)
## Scenarios      Given <state> / When <action> / Then <observable result>   (1–5)
## Constraints    CGO_ENABLED=0; migration needs explicit approval + backup; I18n.tr for
                  strings; quickshell/DankCommon read-only; Upstream-worthy: yes/no
## Acceptance     checkable list, each tied to a scenario or constraint
## Risks          callers touched, data, providers, sync; layers touched (tick list: QML,
                  UI setting, IPC, DB migration, provider, HTTP/CLI)
## Size           t-shirt: S (one layer, <1h) | M (2–3 layers) | L (cross-cutting, schema,
                  new provider); any phase below that doesn't apply, and why
```

Always 8 headings. "Upstream-worthy: yes/no" is a line under Constraints, not a separate
heading; the layers-touched tick list lives under Risks; a skipped phase is noted under Size.

**Order matters: show the spec to the user and get their yes first, then create the issue.**
Ready = the user said yes AND the issue exists.

```bash
gh issue create -R valicaa/dankcalendar --title "<area>: <summary>" --body-file \
  <scratchpad>/issue-body.md --label <enhancement|bug|chore> --label <size:S|size:M|size:L>
```

The title is `area: lowercase summary` (like a commit subject) — one type label, one size
label. `N` is the number at the end of the URL this command prints. The slug is that title's
summary (without the `area:` prefix) as lowercase kebab-case, 2–5 words
(`events: add free/busy check` → `free-busy-check`).

Then create the branch (PM does this too — see the "does itself" list above):

```bash
git fetch origin
git rev-list --count origin/master..master   # must print 0
gh issue develop <N> -R valicaa/dankcalendar --name <feat|fix|chore>/<N>-<slug> --base master --checkout
```

Prefix by issue label: `feat/` for `enhancement`, `fix/` for `bug`, `chore/` otherwise. Don't
`git switch master` for the freshness check above — it breaks if `master` is checked out in
another worktree. If the count is nonzero, ask the user to OK pushing `master` first.

Write `tasks/<N>-<slug>/todo.md` — the work breakdown, one checkbox per task with the agent
that owns it — and commit it: `tasks: plan for <slug>`.

## 3. Break down and delegate

Split the issue into a work breakdown (WBS) in `todo.md`: tasks that each have one deliverable
and one owner. Pick the agent by the hardest thing the task needs:

| Task type | Agent | Model / effort |
|---|---|---|
| Lookup, "where is X", callers, summarise a file, graph query | `dcal-scout` | haiku / low |
| Recipe-shaped edit, standard feature step, tests, docs/tooling | `dcal-builder` | sonnet / medium |
| Design, L plan, cross-cutting change, unclear bug, schema/migration, provider/sync | `dcal-architect` | opus / high |
| Review a diff against the issue + CLAUDE.md (M/L, DB, providers, migrations, sync) | `dcal-reviewer` | opus / high |
| Run `verify-change`, prove it in a dev instance | `dcal-verifier` | sonnet / low |

The Agent tool's `model` param overrides the agent's frontmatter: use `fable` for the hardest
problems (architect failed, subtle concurrency or data-loss risk), `haiku` for bulk mechanical
steps. For a `new-feature` run: the PM owns phases 1–2 and 7, and getting the user's one OK
before phase 6 (merge, deploy, and — if any `.qml` file changed — the graph refresh, asked
together). `dcal-builder` (or `dcal-architect` for L, schema or provider work) does phase 3 on
the branch the PM already created, and — once the OK is given — the merge/deploy/graph-refresh
in 6; `dcal-verifier` does phase 4 and confirms the deploy in 6; `dcal-reviewer` does phase 5
when the review rule below calls for it.

**Review rule (this overrides any other phrasing):** send `dcal-reviewer` for every M/L
change, and for anything touching the DB, migrations, providers or sync — regardless of size.
Otherwise review is optional; if skipped, say so in the verifier's evidence comment (step 4).

**Brief template** — give each subagent only what its task needs:

```markdown
Context:     one paragraph; issue number (`gh issue view N -R valicaa/dankcalendar`); the
             branch (already created — never ask a subagent to create or switch branches);
             files and graph pointers (node ids or `graph-calls.py <path> --grep <name>`)
Goal:        the one deliverable
Constraints: scope limit, rules that apply, what not to touch, commit or not
Acceptance:  the scenarios/criteria this task must satisfy
Deliverable: diff summary + command output / screenshot as evidence, not prose
```

- Independent tasks go out in parallel, in one message. Tasks touching the same file run in
  sequence.
- Parallel edits to one branch conflict; give builders separate files or use
  `isolation: worktree`.

## 4. Track

- Never accept "should work", "tests should pass" or a summary without output. Send it back
  for the evidence, or send `dcal-verifier`.
- Check each report against the issue's acceptance list, item by item.
- Post evidence as an issue comment, short and concrete:
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

- [ ] `dcal-verifier` report posted: all checks pass, feature seen in a dev instance
- [ ] `dcal-reviewer` pass posted when the review rule called for it; blockers fixed and
      re-verified
- [ ] every acceptance item ticked with its evidence, and ticked in the issue body itself
      (`gh issue edit N -R valicaa/dankcalendar --body-file <updated>.md`)
- [ ] issue closed by the merge (`Closes #N` in the `--no-ff` merge commit message)
- [ ] a final issue comment: merge commit hash + deploy confirmation (version, service state)
- [ ] user summary: what changed, how it was proven, what's left, next step (deploy/PR)
- [ ] retrospective: a correction, a wrong tier or a brief that had to be redone → one dated
      rule in `tasks/lessons.md`

Merging, deploying (`deploy-local`) and upstream PRs wait for the user's go-ahead — one
question covers merge + deploy + the QML graph refresh (if any `.qml` file changed). The PM's
own part is getting that go-ahead; `dcal-builder` runs the merge/deploy/graph-refresh,
`dcal-verifier` confirms the deploy (version, service, screenshot).
