# #28 docs: review issue specs on GitHub instead of in chat

- [ ] reorder the spec step in project-manager, new-feature and write-issue: draft → `gh issue create` → owner reviews the link → OK → branch — dcal-builder
- [ ] verify-change section 0 (docs-only): grep for pre-create approval, `check-docs.py` → `docs OK` — dcal-verifier
- [ ] fresh subagent reads only project-manager step 2 and describes the order — dcal-scout
- [ ] 6.1 result commit + PR body — PM
- [ ] 6.2 push, open PR, back to master — dcal-builder
