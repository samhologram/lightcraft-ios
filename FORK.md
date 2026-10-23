# Fork notes: LightCraft for iOS and iPadOS

This repository is a fork of [storytold/lightcraft](https://github.com/storytold/lightcraft) (remote `upstream`) maintained at samhologram/lightcraft-ios (remote `origin`). It adds native iOS/iPadOS apps on top of the unchanged Rust engine.

## The rule

**Never edit upstream files.** Fork work lives only in:

- `apple/` (Rust bridge in `apple/bridge`, Swift package `apple/LightCraftKit`, app in `apple/LightCraft`, scripts, docs)
- `.github/workflows/apple-*.yml`
- `FORK.md`

Everything else is upstream's and must stay byte-identical so merges never conflict. If the engine needs a change, send it upstream. History policy: merge upstream, never rebase.

## Building

See `apple/README.md`.
