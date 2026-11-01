# Contributing to DMAction

Thank you for helping. This guide says how to build and test the package, what a test must do, and
how to propose a change. [ENGINEERING.md](ENGINEERING.md) has the architecture and the
compatibility and release policy.

## Build and test

You need Xcode 16.0 or later (Swift 6.0) and an iOS simulator, and a watchOS one to run the
watchOS tests. CI runs Xcode 16.2, 16.4 and 26.6.

```bash
swift test
```

runs the suite on the Mac. The same suite on a simulator, with warnings as errors:

```bash
xcodebuild test -scheme DMAction -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

and once more under the Thread Sanitizer:

```bash
swift test --sanitize=thread
```

The `watchos` job of CI runs the suite on a watchOS simulator, builds the library for the watchOS
device SDK, and builds `Fixtures/Consumer` for the watchOS Simulator:

```bash
xcodebuild test -scheme DMAction -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
xcodebuild build -scheme DMAction -sdk watchos -destination 'generic/platform=watchOS' -configuration Release SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

`Scripts/prepare-simulator.sh "<device type name>" <version> [iOS|watchOS]` boots the simulator
that a CI job uses, creates its device when the image has none, and prints the udid. It is one of
the scripts that DMDevKit provides (see "The tools").

## The checks CI runs

The checks below are scripts in `Scripts/`, and CI runs them as you do, except
`check-example-project.sh`, which needs XcodeGen, and `check-wrappers.sh`, which CI replaces by the
command it forwards to, `swift run --quiet --package-path Tools devkit check-wrappers`, so that a
fault of the script cannot turn the check into another one. The CI jobs that build and test run the
commands of "Build and test" and of "The example app".

| Script | What it checks |
|---|---|
| `Scripts/lint.sh` | SwiftLint, at the version pinned in `.swiftlint.yml`. The first run fetches that version into `.build/tools` and checks its checksum; runs at once on one checkout do not disturb each other. `--analyze <xcodebuild log>` also runs the analyzer rules |
| `Scripts/check-lint-tool.sh` | that the helper which fetches SwiftLint (DMDevKit's `swiftlint-tool.sh`) is safe to run twice at once: with a fake archive and shims for `unzip` and `curl` it checks that the tool stays whole while another run unpacks and is replaced by a rename, that two first-time runs both succeed, that a wrong checksum never reaches the unpack, and that a failed download or unpack leaves nothing behind |
| `Scripts/check-lint-contract.sh` | that the lint rules fire: it lints the fixtures of `Fixtures/Lint` where their folder says (the root as files of the library, `Domain/` and `Adapters/` as files of that folder, `Outside/` outside the library) and compares the diagnostics of the rules named in `devkit.conf` with the ones each line expects |
| `Scripts/check-wrappers.sh` | that the nine scripts which `WRAPPERS` in `devkit.conf` lists forward to `devkit` faithfully (`lint`, `check-lint-contract`, `check-lint-tool`, `prepare-simulator`, `check-api`, `check-release`, `export-coverage`, `count-tests` and this one): `devkit check-wrappers` copies each into a scratch repository whose path holds a space and, with a shim in place of `swift`, checks the command and the arguments that reach `devkit`, the directory, the exit status and both standard streams, that the script ends in an `exec`, that `DEVELOPER_DIR` and standard input reach `swift` as the caller had them, that the first line is `#!/bin/bash`, and that each script works from any directory. Without `WRAPPERS` it ends with status 2 |
| `Scripts/check-api.sh` | the public interface against `Fixtures/API/public-interface.txt`; `--self-test` runs the cases of its normalisation, which DMDevKit carries; `--since <ref>` prints, without a compiler, the lines the baseline lost, changed or gained since a git ref such as a release tag. A deliberate change of the public API runs it with `--update` and commits the new baseline in the same commit |
| `Scripts/check-release.sh <version>` | that the newest heading of `CHANGELOG.md` is that version, with a release date that is a day of the calendar and notes under it, and that the podspec still names 1.1.0, the version the pod is frozen at; it also compares the release with the one before it, which is the highest release tag below the version that the commit reaches and which the next heading of the changelog must name, and refuses a version that keeps its major version after a removed or changed line of the interface, after a `### Breaking changes` subsection, or when `Scripts/check-api-digester.sh` reports a break since the previous release. It reads the tags, so it needs the history of the commit with its tags: in a shallow clone it ends with status 2 |
| `Scripts/export-coverage.sh <result bundle> <target> <output>` | not a check: it exports the line coverage of the library from a result bundle to LCOV, for CI to upload to Codecov |
| `Scripts/count-tests.sh [--label <text>] <result bundle> <glob>...` | that every test method of the files the globs name ran and passed in the result bundle: a run that lost a test class or skipped a test passes the build and the coverage floor too |
| `Scripts/check-api-digester.sh <ref>` | that swift-api-digester finds no break between the working tree and a git ref, such as the last release: a protocol requirement added without a default, a method that an extension declares and that becomes a requirement, a narrowed generic requirement; `--self-test` runs it on a scratch package. It builds for the host only, and it does not see a changed default value, an added associated type with a default, or the resolution of an overload |
| `Scripts/check-manifest.sh` | the manifest, which declares no dependency, plugin or unsafe flag and does not read the environment; the README's installation manifest built by version, whose resolution pins this package and nothing else; the consumer fixture, the podspec and the uses across isolation domains that the compiler must keep rejecting; `--self-test` runs the reader of the consumer's `Package.resolved` on built-in texts, with no build and no network |
| `Scripts/coverage-gate.sh <result bundle>` | the line coverage of the library |
| `Scripts/check-snippets.sh` | every Swift block of a tracked Markdown file and of a doc comment in `Sources`, each compiled on its own against the checkout, as written: a manifest, a block for iOS, or a command-line tool for the Mac. A warning fails it too |

The checks run code that the branch contains: `Package.swift` and the manifest blocks of the README
are evaluated by Swift Package Manager, the podspec by CocoaPods, and `project.yml` by XcodeGen.
`Tools/Package.swift` and `devkit.conf` are code of the same kind: `devkit.conf` is shell code that
runs with your rights. Before you run the checks on someone else's branch, read what that branch
changes in those files.

## The tools

`Scripts/lint.sh`, `Scripts/check-lint-contract.sh`, `Scripts/check-lint-tool.sh`,
`Scripts/prepare-simulator.sh`, `Scripts/check-api.sh`, `Scripts/check-release.sh`,
`Scripts/export-coverage.sh`, `Scripts/count-tests.sh` and `Scripts/check-wrappers.sh` are wrappers
of [DMDevKit](https://github.com/nikolay-dementiev/DMDevKit), the tooling that DMAction,
DMVariableBlurView and DMUnLoader are to share; DMAction is the first to use it. Each goes to the
repository root, which `devkit` finds with git, so run them in a clone, and runs
`swift run --quiet --package-path Tools devkit <command>` with the arguments it was given, so the
paths that CI and this file name stay as they were. A relative path in an argument is relative to
the root. The other scripts of `Scripts/` have not moved: `check-api-digester.sh`, which
`devkit check-release` runs when it is there, `check-manifest.sh`, `check-snippets.sh`,
`check-example-project.sh` and `coverage-gate.sh`.

- `Tools/Package.swift` is a package of its own. It pins a release of DMDevKit, and
  `Tools/Package.resolved` pins its commit; Dependabot proposes the newer releases. SwiftPM reads
  only the manifest at the root of a dependency, so a package that depends on DMAction does not
  fetch DMDevKit.
- `devkit.conf` holds the settings of this repository that the commands read: the module and the
  library folder, the compiler flags of the interface check, the lint rules and the folder of their
  fixtures, the version the pod is frozen at, and the list of the wrappers (`WRAPPERS`). Each
  setting is written there once, except the compiler flags: `SWIFT_FLAGS` repeats what
  `Package.swift` sets, and no check compares the two, so change both. A change to a command is a
  change to DMDevKit.
- The first run builds `devkit`, takes several seconds and prints the lines that SwiftPM writes
  while it fetches DMDevKit; each next run adds under a second to the script. If `swift run`
  itself fails, a fetch or a build, the script ends with its status, which can be 1, the status
  that the scripts also use for findings.
- A clean checkout gets SwiftLint, at the version that `.swiftlint.yml` pins, by running
  `Scripts/lint.sh`, or alone with
  `swift run --quiet --package-path Tools devkit swiftlint-fetch 0.65.1`.
  Both need `curl`, `unzip` and `shasum`. `.swiftlint.yml` can pin only a version that DMDevKit
  has a checksum for: for another one `Scripts/lint.sh` ends with status 2 and says so, so a
  bump of SwiftLint waits for a DMDevKit release that knows the version.
- `swift run --quiet --package-path Tools devkit --help` lists the commands.

## The example app

`Examples/DMActionExample` uses the package from this checkout. Its view model tests, a UIKit
test and a UI test with the accessibility audit run with:

```bash
xcodebuild test -project Examples/DMActionExample/DMActionExample.xcodeproj -scheme DMActionExample -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

The Xcode project is generated with XcodeGen 2.45.3 from `Examples/DMActionExample/project.yml`,
and both are committed. Change the spec, not the project:
`Scripts/check-example-project.sh --update` regenerates the project, and
`Scripts/check-example-project.sh` checks that the two agree. CI does not install XcodeGen, so this
check is yours to run before you commit a change to the example's project.

## Tests

- XCTest, through the public API only: no `@testable import`.
- One `makeSUT()` factory per test class, and hand-written spies that record calls.
- Names say the subject, the condition and the expected result:
  `test_<subject>_<condition>_<expected>`.
- In a test with two or more assertions, every assertion carries a message.
- A test must be able to fail. Show it red against the code before your change, or, for a test of
  behaviour that already holds, with a temporary change of the code it covers.
- A fix starts with a test that reproduces the defect.

## Commits and pull requests

- One topic per commit, with a conventional prefix: `test:`, `fix:`, `feat:`, `refactor:`, `docs:`,
  `chore:`, `ci:` or `perf:`.
- The commit with a failing test comes before the commit that makes it pass.
- Pull requests go to `main` and are merged with a merge commit, so the test and fix pairs stay
  visible.
- A review, by a person or by an automated reviewer, follows the lanes of
  [Documentation/Review/README.md](Documentation/Review/README.md).
- A change that people using the package can notice gets an entry in `CHANGELOG.md`.

## Releases

A release starts from a tag that is the version itself, such as `1.1.0`, on a commit of `main`:
merge first, then tag. Before the tag is pushed:

1. The newest heading of `CHANGELOG.md` is `## [<version>] -` with the release date and the notes
   under it. `Scripts/check-release.sh <version>` checks it, in a clone that has the history and
   the tags (`git fetch --unshallow --tags` otherwise). The README's installation manifest
   asks for the version being released, `from: "<version>"`, and `Scripts/check-manifest.sh`
   checks it against that heading, so the release pull request updates both together. The podspec
   stays at 1.1.0, because the pod is frozen.
2. Every breaking change, as ENGINEERING.md defines it, needs a new major version, with no
   exception for a small one. A removed or changed line of the interface is one:
   `Scripts/check-api.sh --since <previous version>` lists them. A change of behaviour is another,
   and the notes of the release declare it in a `### Breaking changes` subsection, in any letter
   case, because no script can see behaviour: a change listed under `### Changed` alone does not
   count.
   `Scripts/check-release.sh` refuses a version that keeps the major version of the previous one
   when it finds either, or when `Scripts/check-api-digester.sh <previous version>` reports a break,
   such as a requirement added to a protocol without a default, which the lines show only as an
   added one. Lines that were only added pass the line check, and they are additive only after a
   review that none adds an overload that makes an existing call ambiguous: no script sees that, nor
   the order of the cases of an enum or of the statements in the body of an inlinable function. A
   green digester is evidence, not proof: it does not see a changed default value either.
   It cannot tell a line that a new compiler reworded from a line that the code changed, so both
   count. Run `Scripts/check-api.sh` first, since the baseline is the interface of the library
   only while that check passes.
3. The library's tests pass on an iOS 17 simulator, the oldest version the package supports. CI's
   oldest runtime is iOS 18.5, so this run is local:
   `xcodebuild test -scheme DMAction -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`.

On the tag, the release workflow runs the check, makes sure the tagged commit is on `main`, runs the
whole CI workflow, makes sure the tag still points at the commit CI tested, and drafts a GitHub
release from the changelog section. Publishing the release stays a manual step, and nothing goes
to the CocoaPods trunk.

After the tag, open the package's page on the Swift Package Index,
https://swiftpackageindex.com/nikolay-dementiev/DMAction, and check that the new version and its
documentation are listed. The index picks up a tag on its own schedule, so they may not be listed at
once; check again later. `.spi.yml` configures the documentation build; no script or CI job checks
the index.

## Security

Do not report a vulnerability in a public issue. See `SECURITY.md`.
