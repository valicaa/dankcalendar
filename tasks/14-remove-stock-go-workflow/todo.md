# Issue #14 — ci: remove broken stock go workflow

- [ ] Delete `.github/workflows/go.yml`; confirm nothing else references it; `go-ci.yml` untouched — dcal-builder
- [ ] `verify-change` static checks on the branch — dcal-verifier
- [ ] PR opened (6.2); PR checks show no `build` job from `go.yml` — dcal-builder, checks read by PM
