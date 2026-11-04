# CI

The repository's `.github/workflows/ci.yml` calls the family's pinned swift-ci workflow for this package
(`package-path: Apps/KittyCode`), configured by `action.json`; run the same checks here with `.ci/swift-ci local`.

Each change to it runs quality (swift-format, SwiftLint metrics, the shipped-library discipline over `Sources`, the
analyzers) and the macOS debug tests, release and the other sanitizers nightly or manually. The package needs
AppKit, so there is no Linux leg.

`baselines/` accepts the findings that predate the analyzers' adoption (deadwood 2, dolly 565; most of dolly's are test-code
notes, which never fail); only a new one fails. Shrink them by fixing the code.
