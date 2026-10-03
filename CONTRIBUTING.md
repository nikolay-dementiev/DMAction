# Contributing to DMAction

Thank you for helping. This guide says how to build and test the package, what a test must do, and
how to propose a change.

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
| `Scripts/check-api.sh` | the public interface against `Fixtures/API/public-interface.txt`. A deliberate change of the public API runs it with `--update` and commits the new baseline in the same commit |
| `Scripts/check-manifest.sh` | the manifest, the README's installation manifest built by version, the consumer fixture, the podspec and the uses across isolation domains that the compiler must keep rejecting |
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

1. The podspec names that version, and the newest heading of `CHANGELOG.md` is `## [1.1.0] -` with
   the release date and the notes under it. `Scripts/check-release.sh 1.1.0` checks them.
2. The library's tests pass on an iOS 17 simulator, the oldest version the package supports. CI's
   oldest runtime is iOS 18.5, so this run is local:
   `xcodebuild test -scheme DMAction -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`.

On the tag, the release workflow runs the check, makes sure the tagged commit is on `main`, runs the
whole CI workflow, makes sure the tag still points at the commit CI tested, and drafts a GitHub
release from the changelog section. Publishing the release, and the pod, stays a manual step.

## Security

Do not report a vulnerability in a public issue. See `SECURITY.md`.
