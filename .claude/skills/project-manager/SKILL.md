---
name: project-manager
description: MAIN SESSION ONLY — use at the start of every user request for work in Dank Calendar — features, bugs, questions about the code, refactors, docs, tooling, "can you…". The main session acts as project manager — it elicits intent, writes the spec, breaks it down and delegates all technical work to the .claude/agents roster, then verifies the evidence. A subagent given a brief does not load this skill or act as PM; it does the brief itself (see each agent's own instructions).
---

# Project manager

The main session is the PM. It talks to the user, owns the issue, dispatches subagents,
checks their evidence and reports back. It does not read source, edit code, run builds or
debug. Keep the PM's context small and about the user's intent; subagents carry the file dumps.

This skill decides *who* does the work; process skills may still run *inside* a step
(superpowers brainstorming within Elicit, systematic-debugging by `dcal-architect`).

**The PM does itself:** talk to the user; read CLAUDE.md, skills, `tasks/lessons.md`, issues
and subagent reports; write the issue body and briefs; create and update the issue
(`gh issue create|comment|edit|reopen -R valicaa/dankcalendar`); create the branch (step 2, or a
step-0 `docs/<slug>` branch — the only branch operations the PM runs); write
`tasks/<N>-<slug>/todo.md`, keep it ticked, and commit everything under `tasks/` — plan, result,
lessons, any deliverable that lives there — as `tasks:` commits (`tasks: plan for <slug>` in
step 2, `tasks: result for <slug>` in `new-feature` 6.1). Agents may edit `tasks/` but never
commit it; a merge of `origin/master` (`new-feature` Conflicts) authors nothing there, so it
isn't one. Also: write PR bodies; post every issue and PR comment (agents never post); cheap
read-only status checks needed to decide (`git status`, `git log --oneline`, `check-docs.py`,
`gh pr view`). Everything else goes to a subagent, including "quick" lookups.

**Branches.** One feature is worked on at a time: the one whose branch is checked out, from
step 2 until `new-feature` 6.2 opens its PR and returns the checkout to `master`. Then the next
one may start; several PRs may await the owner, and each merge gets its own 6.4. Review rounds,
conflicts and 6.4 need the checkout on `master`, so they wait for the feature being worked to
reach its PR (or, with the user's OK, for it to be parked). In phases 3–5 no agent creates or
switches branches. The branch-operating procedures — phase 6 (including review rounds), step
0's trivial PR, `sync-upstream`, `deploy-local` (and its rollback) and `upstream-pr` — are run
by `dcal-builder` on the PM's brief, in the main checkout (`upstream-pr` in its own `pr/<slug>`
worktree). `master` moves only when the owner merges a PR on GitHub: nobody commits on it (the
check-docs hook blocks it) or pushes it.

## 0. Does this need an issue at all?

A question or a read-only lookup ("where is X", "why does Y happen") needs neither an issue nor
a branch — answer it (send `dcal-scout` if it needs the code) and stop here. Only an actual
change goes on. Two trivial changes skip the issue, but not the PR — every change reaches
`master` as a PR the owner merges; everything else goes through steps 1–5:

- **Anything in `tasks/lessons.md`** (a new rule, or a typo inside one): always the PM, as a
  `tasks: <summary>` commit. While a feature branch is checked out (phases 2–5, or a review
  round) it rides along in that branch's next `tasks:` commit; otherwise a trivial branch.
- **A typo in any other doc** (CLAUDE.md, a skill, an agent): a `dcal-builder`, as a
  `docs: <summary>` commit on a trivial branch — only while the main checkout is on `master`.

A trivial branch is `docs/<slug>`, no issue; `<slug>` comes from the commit summary by
`write-issue`'s slug rule. The check-docs hook takes commits on it only while every uncommitted
path is a doc (`.claude/**.md`, `tasks/`, CLAUDE.md, a root `*.md`). The committer creates it:

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git pull --ff-only origin master
git switch -c docs/<slug> || exit 1
```

After the commit, `dcal-builder` verifies (`.claude/tools/check-docs.py` prints `docs OK`,
`git diff --check master...HEAD` prints nothing), pushes with `new-feature` 6.2's push block
(`<branch>` = `docs/<slug>`), opens the PR with this block and returns with 6.2's last block.
The PM-written body (what, why, attribution) closes no issue:

```bash
! grep -qiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]+' <scratchpad>/pr-docs-<slug>.md && tail -1 <scratchpad>/pr-docs-<slug>.md | grep -qF 'Generated with [Claude Code]' || { echo "STOP: a step-0 PR body closes no issue and ends with the attribution"; exit 1; }
gh pr create -R valicaa/dankcalendar --base master --head docs/<slug> --title "$(git log -1 --format=%s docs/<slug>)" --body-file <scratchpad>/pr-docs-<slug>.md
```

The PM gives the owner the link. Once it is merged and the checkout is on `master`,
`dcal-builder` runs 6.4's first block; only docs, so nothing is deployed.

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

The template (8 headings), the feature/bug/chore variants, and the title/label/slug rules live
in `write-issue`. Write the body with `write-issue`, show it to the user and get their yes, then
create the issue with its `gh issue create` command. Ready = the user said yes AND the issue
exists.

Then create the branch — in the main checkout, which must be on `master` with a clean tree
(one feature worked at a time — see Branches; with the user's OK a checked-out one can be parked:
`dcal-builder` commits its work, then `git switch master`):

```bash
git branch --show-current                      # must print master
git status --short                             # must print nothing
git fetch origin
git pull --ff-only origin master
git rev-list --count origin/master..master     # must print 0
gh issue develop <N> -R valicaa/dankcalendar --name <feat|fix|chore>/<N>-<slug> --base master --checkout
```

Prefix by issue label — see `write-issue`'s Branch name section.
`gh issue develop` creates the branch on GitHub from origin's `master`: the pull brings a
local `master` that is behind up to date (phases 4–5 diff against it), and a local-only commit
would be missing from the branch. `master` never holds local commits, so a nonzero count or a
refused pull (diverged) means something went wrong: stop and take it to the user.

Write `tasks/<N>-<slug>/todo.md` — the work breakdown through `new-feature` 6.1, one line per
task, `- [ ] <deliverable> — <agent>`, with agents from the table below — and commit it as
`tasks: plan for <slug>`. The branch exists on origin (`gh issue develop` made it) but carries no
commits there until 6.2 pushes it. The PR, merge and deploy are tracked in issue comments.

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
steps. Who does which `new-feature` phase is in that skill's header (phase 6: two `dcal-builder`
briefs around the owner's merge — 6.2 opens the PR, 6.4 pulls and deploys). `sync-upstream` and
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
  Verdict: pass | blockers found (N)
  Review: skipped — <why>          (verifier comment only, when the review rule doesn't apply)
  - check: pass/fail — `<command>` → `<real output excerpt>`
  ```
  `gh issue comment <N> -R valicaa/dankcalendar --body-file <scratchpad>/evidence.md` — always
  `--body-file`: a quoted `git commit` in an inline `--body` trips the check-docs hook. One
  comment per verifier run and per reviewer run.
- Scope grows (new layer, migration, extra setting): stop and raise a change request with the
  user — what changed, cost in size, options. Don't absorb it silently.
- A subagent fails twice: re-brief with what was missing, or escalate one tier (builder →
  architect → `model: fable`). Don't take over the work yourself.
- Keep `tasks/<N>-<slug>/todo.md` ticked as tasks land (through 6.1; the last ticks go in the
  `tasks: result` commit) — the PM's own job. Review requests come from the owner or
  `gh pr view <PR> -R valicaa/dankcalendar --json state,reviewDecision,reviews,comments`.

## 5. Close — Definition of Done

- [ ] `dcal-verifier` report posted: all checks pass, seen in a dev instance (docs-only:
      `verify-change` section 0); `dcal-reviewer` pass posted when the review rule calls for it
- [ ] every acceptance item ticked with its evidence, and ticked in the issue body itself —
      only the boxes under `## Acceptance`, never the Risks layer list:
      `gh issue view N -R valicaa/dankcalendar --json body -q .body > <scratchpad>/body.md`,
      tick them in that file, then
      `gh issue edit N -R valicaa/dankcalendar --body-file <scratchpad>/body.md`
- [ ] retrospective (a correction, a wrong tier, a redone brief) → a dated rule in
      `tasks/lessons.md`; `todo.md` ticked through 6.1; both in `tasks: result for <slug>`
- [ ] PR open (6.2), its URL on the issue, main checkout on an up-to-date `master`; user
      summary: what changed, how it was proven, the PR link, what's left — no merge question
- [ ] after the owner merges (the merge closes the issue): 6.4 done, a final issue comment with
      the merge commit + deploy confirmation, or "docs-only" (`new-feature` phase 6 also covers
      a failed deploy and a PR closed unmerged)

The PM never asks for a merge, push or deploy OK in chat: the owner merges the PR on GitHub,
and that is the OK to deploy (`new-feature` 6.4 says how the PM learns of it). Only the QML
graph refresh (LLM cost) and `upstream-pr` still wait for the user's word.
