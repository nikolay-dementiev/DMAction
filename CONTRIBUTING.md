# Contributing to DMAction

Thank you for helping. This guide says how to build and test the package, what a test must do, and
how to propose a change. [ENGINEERING.md](ENGINEERING.md) has the architecture and the
compatibility and release policy.

## Build and test

You need Xcode 16.0 or later (Swift 6.0) and an iOS simulator. CI runs Xcode 16.2, 16.4 and 26.6.

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

## The checks CI runs

The checks below are scripts in `Scripts/`, and CI runs them as you do, except
`check-example-project.sh`, which needs XcodeGen. The CI jobs that build and test run the commands
of "Build and test" and of "The example app".

| Script | What it checks |
|---|---|
| `Scripts/lint.sh` | SwiftLint, at the version pinned in `.swiftlint.yml`. The first run fetches that version into `.build/tools` and checks its checksum. `--analyze <xcodebuild log>` also runs the analyzer rules |
| `Scripts/check-lint-contract.sh` | that the lint rules fire: it lints the fixtures of `Fixtures/Lint` and compares the diagnostics of the import, force unwrap and termination rules with the ones each line expects |
| `Scripts/check-api.sh` | the public interface against `Fixtures/API/public-interface.txt`; `--self-test` runs the cases of its normalisation; `--since <ref>` prints, without a compiler, the lines the baseline lost, changed or gained since a git ref such as a release tag. A deliberate change of the public API runs it with `--update` and commits the new baseline in the same commit |
| `Scripts/check-release.sh <version>` | that the newest heading of `CHANGELOG.md` is that version, with a release date that is a day of the calendar and notes under it, and that the podspec still names 1.1.0, the version the pod is frozen at; it also compares the release with the one below it in the changelog and refuses a version that keeps its major version after a removed or changed line of the interface, after a `### Breaking changes` subsection, or when `Scripts/check-api-digester.sh` reports a break since the previous release |
| `Scripts/check-api-digester.sh <ref>` | that swift-api-digester finds no break between the working tree and a git ref, such as the last release: a protocol requirement added without a default, a method that an extension declares and that becomes a requirement, a narrowed generic requirement; `--self-test` runs it on a scratch package. It builds for the host only, and it does not see a changed default value, an added associated type with a default, or the resolution of an overload |
| `Scripts/check-manifest.sh` | the manifest, which declares no dependency, plugin or unsafe flag and does not read the environment; the README's installation manifest built by version, whose resolution pins this package and nothing else; the consumer fixture, the podspec and the uses across isolation domains that the compiler must keep rejecting |
| `Scripts/coverage-gate.sh <result bundle>` | the line coverage of the library |
| `Scripts/check-snippets.sh` | every Swift block of a tracked Markdown file and of a doc comment in `Sources`, each compiled on its own against the checkout, as written: a manifest, a block for iOS, or a command-line tool for the Mac. A warning fails it too |

The checks run code that the branch contains: `Package.swift` and the manifest blocks of the README
are evaluated by Swift Package Manager, the podspec by CocoaPods, and `project.yml` by XcodeGen.
Before you run them on someone else's branch, read what that branch changes in those files.

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
- A change that people using the package can notice gets an entry in `CHANGELOG.md`.

## Releases

A release starts from a tag that is the version itself, such as `1.1.0`, on a commit of `main`:
merge first, then tag. Before the tag is pushed:

1. The newest heading of `CHANGELOG.md` is `## [<version>] -` with the release date and the notes
   under it. `Scripts/check-release.sh <version>` checks it. The README's installation manifest
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

## Security

Do not report a vulnerability in a public issue. See `SECURITY.md`.
