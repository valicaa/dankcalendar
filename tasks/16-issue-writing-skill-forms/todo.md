# #16 — standardize issue writing with a skill and github forms

Spec: `gh issue view 16 -R valicaa/dankcalendar --comments`

- [x] Map every place that holds the issue template, title/label/slug rules and the fork-only path / docs-only lists — dcal-scout
- [x] `write-issue` skill (headings, feature/bug/chore variants, title/area/label/slug rules, checklist, worked example); project-manager step 2 + CLAUDE.md point to it — dcal-builder (306f1a5, rounds af0c4d8, bc55dad, 9b77ab6, 7365cec)
- [x] `.github/ISSUE_TEMPLATE/{feature,bug,chore}.yml` + `config.yml`; `.github/ISSUE_TEMPLATE/` added to every fork-only list and docs-only regex; REVIEW_RULES entry — dcal-builder (373336a, 6222b99, 606d73b)
- [x] Forms schema-validated against SchemaStore before merge — dcal-builder, dcal-verifier
- [ ] After merge (6.4): the chooser shows Feature/Bug/Chore with no blank issue; one `TEST (form check): …` issue per form is filed, then closed — dcal-builder + PM
- [x] Review the diff against #16's scenarios and acceptance — dcal-reviewer (3 runs; findings fixed or decided)
- [x] Literal walkthrough: a fresh agent writes issues from the skill alone; they pass the checklist — general-purpose (3 runs; last major fixed in 7365cec)
- [x] Verify: check-docs, diff --check, docs-only test — dcal-verifier (pass)

PR, merge and the post-merge form check are tracked in comments on #16.
