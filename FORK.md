# Fork notes: LightCraft for iOS and iPadOS

This repository is a fork of [storytold/lightcraft](https://github.com/storytold/lightcraft) (remote `upstream`),
maintained at [samhologram/lightcraft-ios](https://github.com/samhologram/lightcraft-ios) (remote `origin`). It adds
native iOS/iPadOS apps on top of the unchanged Rust engine. `main` is this fork's main branch.

## The rule

**Never edit upstream files.** Fork work lives only in:

- `apple/` (Rust bridge `apple/bridge`, Swift package `apple/LightCraftKit`, app `apple/LightCraft`, tests, scripts, docs)
- `.github/workflows/apple-*.yml` (none yet)
- `FORK.md`

Everything else is upstream's and stays byte-identical, so importing upstream never conflicts. If the engine needs a
change, send it upstream.

## Importing the original code

```bash
apple/scripts/sync-upstream.sh
```

It adds the `upstream` remote if missing, refuses if any upstream file was changed in the fork, merges `upstream/main`
into `main` (merge commit, never rebase), then reruns the bridge gate, the xcframework build and the coverage checks.
Push with `git push origin main` when they pass.

## CI

Upstream's workflows (`.github/workflows/*.yml`) come along with the code. Fork commits carry `[skip ci]` so pushes to
`main` don't start them.

## Building

See `apple/README.md`; the porting recipe is `apple/docs/COOKBOOK.md`.
