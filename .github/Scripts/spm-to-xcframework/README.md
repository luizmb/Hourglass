# Vendored: `spm-to-xcframework`

Builds a distribution-ready, **importable** `.xcframework` from this SwiftPM package for the
release pipeline (see `.github/workflows/release.yml`).

A SwiftPM library builds as a static archive + a loose `.swiftmodule`, which `-create-xcframework`
cannot turn into a Swift-consumable framework. This tool temporarily rewrites the library product to
`.dynamic`, archives one slice per Apple platform (device + simulator) with
`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, injects the `.swiftinterface`/`.swiftmodule` and a
`module.modulemap` into each framework, and merges them into one `.xcframework`.

## Provenance

- Upstream: <https://github.com/justinwojo/spm-to-xcframework>
- Pinned commit: `c2d1ec0af1d899da1b4f536869233f4355d2fac4`
- License: MIT (see `LICENSE`) — Copyright (c) 2026 Justin Wojciechowski

Vendored (rather than fetched at CI time) for supply-chain determinism: the exact bytes are pinned in
git and reviewed. `spm-to-xcframework` is the upstream self-contained single-file build — Python 3.9+,
standard library only, no `pip install`.

## Update

Re-vendor from a newer upstream commit:

```bash
git clone https://github.com/justinwojo/spm-to-xcframework.git
cp spm-to-xcframework/spm-to-xcframework .github/Scripts/spm-to-xcframework/spm-to-xcframework
cp spm-to-xcframework/LICENSE            .github/Scripts/spm-to-xcframework/LICENSE
# update the pinned commit above
```

## Local use

On a machine with a **custom Xcode DerivedData / build location**, builds land outside the tool's
`-derivedDataPath` and it reports "zero .swiftinterface". Temporarily set
`IDEBuildLocationStyle=DerivedData` (and clear `IDECustomDerivedDataLocation`) for the run, then
restore. CI runners use the default location and are unaffected.
