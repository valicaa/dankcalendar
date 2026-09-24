# #9 — finish changes with a PR the owner merges

Spec: `gh issue view 9 -R valicaa/dankcalendar --comments`

- [ ] Rewrite phase 6 for the PR flow (new-feature, project-manager, deploy-local, dcal-builder, CLAUDE.md); failed deploy → rollback + reopen + new PR; end on master — dcal-architect
- [ ] Review the diff against #9's scenarios and acceptance — dcal-reviewer
- [ ] Literal walkthrough of the new phase 6 on a test issue + test PR (created and closed) — fresh general-purpose agent
- [ ] Verify: check-docs, diff --check, docs-only test — dcal-verifier
- [ ] Open the PR for #9, return the main checkout to master — dcal-builder
