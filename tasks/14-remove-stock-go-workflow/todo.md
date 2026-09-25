# Issue #14 — ci: remove broken stock go workflow

- [x] Delete `.github/workflows/go.yml`; confirm nothing else references it; `go-ci.yml` untouched — dcal-builder (099df27)
- [x] `verify-change` static checks on the branch — PM (check-docs, diff --check, scope; posted on #14)
- [ ] PR opened (6.2); PR checks show no `build` job from `go.yml` — dcal-builder, checks read by PM
