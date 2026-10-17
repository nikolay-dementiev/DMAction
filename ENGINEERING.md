# Engineering standard

This is the standard DMAction is built by: what a change to its public interface and behaviour
costs, what the package is made of, and which toolchains and platforms it promises.
[CONTRIBUTING.md](CONTRIBUTING.md) has the commands, the checks CI runs, the rules for tests and
the release steps. This file does not repeat them.

## Public API and behaviour

DMAction is a published library, so what a consumer can see is a contract: every `public`
declaration and every observable behaviour. Each change belongs to one of three classes:

- **none**: no declaration and no observable behaviour changes.
- **additive**: new declarations only, with `Fixtures/API/public-interface.txt` updated in the same
  commit, and nothing a consumer must do. A raised minimum version of a dependency can be additive
  under the conditions below the table.
- **breaking**: anything else.

The rule is strict and has no carve-out: every change of observable behaviour is breaking. That
includes a crash that stops happening and a behaviour brought back in line with the documentation.
A breaking change needs the maintainer's decision, a migration note in `CHANGELOG.md` and a major
version.

| Change | Class | Release |
|---|---|---|
| A changed default value | breaking | major |
| A new case in a public enum that a consumer can switch over (the package declares none today) | breaking | major |
| A new protocol requirement without a default implementation | breaking | major |
| A new protocol requirement with a default implementation | additive or breaking, see below | minor or major |
| An added overload | additive, or breaking if an existing call now resolves to it or becomes ambiguous | minor or major |
| Depending on a new major version of a dependency | breaking | major |
| Raising the minimum version of a dependency within the same major | additive or breaking, see below | minor or major |
| A CI or tool pin, such as a runner image or the SwiftLint version | none | patch, or no release |
| A pure refactor | none | patch, or no release |
| A crash that stops happening | breaking | major |

A new protocol requirement with a default implementation is additive only when its name is new to
the protocol and to its extensions, and a review finds no member of a conformer that the
requirement would capture. A name that a protocol extension already declares changes how a call is
dispatched: the extension method was called statically and the requirement is called dynamically,
so a conformer's own member of that name starts to be called. That is a change of behaviour, so it
is breaking.

Raising the minimum version of a dependency within the same major version is additive only when it
moves no platform floor, changes no behaviour and asks nothing of a consumer. It then needs a minor
release and its own line in the changelog. A raise that does any of these is breaking.

The package has no dependency today.

Who checks. The `api` job of CI runs `Scripts/check-api.sh` on every pull request and fails it when
the public interface differs from the baseline; it also writes to the job summary the delta against
the base of the pull request and what swift-api-digester finds against the last release.
`Scripts/check-release.sh` runs on the version tag, and before it by whoever releases: it refuses a
version that keeps the major version of the previous release when the baseline lost or changed a
line since that release, when the digester reports a break since that release, or when the notes of
the version have a `### Breaking changes` subsection. The digester gives a verdict on what the lines
show only as an added one: a protocol requirement added without a default, a method that an
extension declares and that becomes a requirement. It names a narrowed generic requirement too,
which the lines show as a changed one. It does not see a changed default value, an added associated
type with a default or the resolution of an overload, which stay with `Scripts/check-api.sh` and
review, and it builds for the host only, so an API behind `#if os(iOS)` would not be compared (the
package has none). A green digester is evidence, not proof. The pull request template asks for the
class, the changes of observable behaviour and the release the change needs. The reviewer applies
the rest: that the baseline changes in the same commit as the declaration; whether an added line
adds an overload that makes an existing call ambiguous, which no script sees; and every change of
observable behaviour that the notes do not declare, which a test catches only where a test pins the
behaviour. A change of behaviour is caught by a test that pins it, not by the interface checks: with
the nested delivery of 1.0.x restored in a scratch clone,
`test_run_withSynchronousProducers_startsTheFallbackAfterThePrimaryReturns` fails, while
`Scripts/check-api.sh` still reports that the interface matches the baseline and
`Scripts/check-api-digester.sh 1.1.0` finds no break.

## Deprecation

No compiler deprecation attribute ships in a 1.x release. Its warning appears at every use of the
symbol and fails a consumer that builds with warnings as errors, so it would turn a notice into a
breaking change. A symbol is retired in the documentation instead: the replacement and a
migration example say what to use. The next major version removes it.

## History

Version 1.1.0 changed behaviour under a minor version (`CHANGELOG.md`, 1.1.0, "Changed"). Under
the rules above it would have needed a major version. The rules apply from the release after
1.1.0.

## The package as it is

- **One layer.** The library imports Foundation and, where the module exists, `os`. It has no UI,
  no third-party dependency and no build plugin. `Scripts/lint.sh` enforces the imports: the custom
  rule `domain_imports` reports any other import in the library folder, except one that follows a
  block comment on the same line.
- **Composition as data.** `fallbackTo` and `retry` build values and run nothing. What an action
  runs is held as data (`ActionPlan`) and one internal type (`ActionRun`) runs it. `retry` stores
  its count and `fallbackTo` joins the steps of its operands into one list, so neither nests a run.
- **One delivery.** A run of the library's actions delivers at most one result. A later completion
  of the same run is ignored.
- **No `Sendable`.** Nothing public is `Sendable` and no closure type is `@Sendable`. An action is
  used inside one isolation domain.
- **Documented limits.** What the library enforces and what it cannot promise are in the DocC
  article Running Actions (`Sources/DMAction/DMAction.docc/RunningActions.md`) and in the README,
  "Behaviour your app must know". This file points to them and does not restate them. A change of
  one of those limits is a change of behaviour.
- **Composition root.** The public initializers of the library's actions, `fallbackTo` and `retry`
  create every concrete action. A run creates only its own internal state. There is no global
  configuration and no singleton.
- **The library never stops its host.** No `fatalError`, `preconditionFailure`,
  `assertionFailure`, `precondition`, `assert`, `dispatchPrecondition`, `abort` or `exit`, no force
  unwrap, no `try!` and no `as!`. A failure reaches the caller through the result of the run.
  `Scripts/lint.sh` enforces this over `Sources`: the custom rule `no_process_termination` and
  SwiftLint's `force_unwrapping`, `force_try` and `force_cast`. The force unwrap rule has no
  exemption for a call with a literal argument, so `URL(string: "...")!` is reported too.
- **The rules are proved.** A rule that never matches reports nothing, so
  `Scripts/check-lint-contract.sh` lints the fixtures of `Fixtures/Lint` and proves that
  `domain_imports`, `force_unwrapping` and `no_process_termination` fire on the lines that expect
  them and on no other line. CI runs it right after `Scripts/lint.sh`.

## Toolchain and platforms

- The manifest declares `swift-tools-version: 6.0` and the Swift 6 language mode, so the package
  needs Xcode 16.0 or later. `ExistentialAny` is on in every target.
- The declared platforms are iOS 17.0 and watchOS 7.0. Raising either platform floor, or the
  `swift-tools-version`, is a breaking change.
- `.github/workflows/ci.yml` is the place that says what CI runs; this file does not restate it.
  The policy needs four facts. The oldest iOS runtime that CI runs is iOS 18.5. iOS 17.5 runs
  locally before a release (CONTRIBUTING.md, "Releases"). The `floor` job runs Swift 6.0, the
  oldest compiler line the manifest allows. watchOS is built by the `podspec` job, and no test runs
  there.
- "Oldest tested runtime" and "oldest supported version" are different statements. The supported
  version is a promise: the platforms the manifest declares. The tested runtime is evidence: the
  oldest runtime a test has run on. That is iOS 17.5 against a promise of iOS 17.0, and none for
  watchOS.
- No dependency without the maintainer's approval. `Scripts/check-manifest.sh` rejects any
  dependency in the manifest, named, so a dependency cannot land without a change of that check
  in the same pull request, where the reviewer sees it. It also rejects a plugin on any target,
  an unsafe flag and a manifest that reads the environment, and it requires that a consumer of
  the README's installation manifest resolves this package only.
- XCTest is the test framework. Another one comes only by the maintainer's decision.
- The manifest sets no `defaultIsolation`: it would change the inferred isolation of public
  declarations, which is observable behaviour.

## Where the rest lives

- [CONTRIBUTING.md](CONTRIBUTING.md): how to build and test, the checks CI runs, the rules for
  tests, commits and releases.
- `Sources/DMAction/DMAction.docc`: what each symbol does, and how a run behaves.
- [CHANGELOG.md](CHANGELOG.md): the history of every release.
- [README.md](README.md): installation and usage.
