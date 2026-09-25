# #16 — standardize issue writing with a skill and github forms

Spec: `gh issue view 16 -R valicaa/dankcalendar --comments`

- [ ] Map every place that holds the issue template, title/label/slug rules and the fork-only path / docs-only lists — dcal-scout
- [ ] `write-issue` skill (headings, feature/bug/chore variants, title/area/label/slug rules, checklist, worked example); project-manager step 2 + CLAUDE.md point to it — dcal-builder
- [ ] `.github/ISSUE_TEMPLATE/{feature,bug,chore}.yml` + `config.yml`; `.github/ISSUE_TEMPLATE/` added to every fork-only list and docs-only regex — dcal-builder
- [ ] Forms validated by real test issues on the fork (created, then closed) — dcal-builder
- [ ] Review the diff against #16's scenarios and acceptance — dcal-reviewer
- [ ] Literal walkthrough: fresh agent writes an issue for a sample request using only the skill; result passes the checklist — general-purpose
- [ ] Verify: check-docs, diff --check, docs-only test — dcal-verifier
