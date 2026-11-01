---
name: public-api-and-documentation
description: Review a change to DMAction for the class of the change, the baseline of the public interface, the changelog and the documented limits. Use it on any change that touches a public declaration, an observable behaviour or a document that people using the package read.
---

# Public API and documentation

The question of this lane: is the change classified as ENGINEERING.md classifies it, and does
everything that people using the package read say so? The lane applies the rules of the repository
and states none of its own. Report each finding in the format of
[Documentation/Review/README.md](../../../Documentation/Review/README.md).

## What it checks

- The class of the change, none, additive or breaking, is stated and is right. A change of
  observable behaviour is breaking, including a crash that stops happening.
  (ENGINEERING.md, "Public API and behaviour")
  (AGENTS.md, "Classify every change")
- `Fixtures/API/public-interface.txt` changes in the same commit as the declaration. The check
  sees only the tip of the branch, so it cannot tell which commit changed it.
  (ENGINEERING.md, "Public API and behaviour")
- An added overload that makes an existing call ambiguous: no script sees it. A protocol
  requirement with a default implementation whose name a protocol extension already declares, or
  that a member of a conformer would capture: the digester reports part of this, and a review
  decides the rest. (ENGINEERING.md, "Who checks.")
  (ENGINEERING.md, "a review finds no member of a conformer that the requirement would capture")
- A breaking change without the maintainer's decision, a migration note in `CHANGELOG.md` and a
  major version. For a change of behaviour the notes declare it in a `### Breaking changes`
  subsection, because no script sees behaviour. (ENGINEERING.md, "A breaking change needs the
  maintainer's decision") (CONTRIBUTING.md, "Every breaking change, as ENGINEERING.md defines it")
  (CONTRIBUTING.md, "a change listed under `### Changed` alone does not count")
- A compiler deprecation attribute in a 1.x release. (ENGINEERING.md, "Deprecation")
- A change that people using the package can notice, with no entry in `CHANGELOG.md`.
  (CONTRIBUTING.md, "A change that people using the package can notice gets an entry")
- A change to a documented limit that leaves the DocC article Running Actions or the README as it
  was. (ENGINEERING.md, "Documented limits")
- The release the change needs is stated in the pull request.
  (PR template, "The release it needs")

## What it ignores

- What a CI script already enforces: `Scripts/lint.sh` (including the rule that every public symbol
  is documented), `Scripts/check-api.sh` against the baseline, `Scripts/check-api-digester.sh`
  (evidence, not proof), `Scripts/check-manifest.sh`, `Scripts/check-snippets.sh` (the Swift
  examples compile) and `Scripts/coverage-gate.sh`.
- How the implementation is built: that is the lane architecture-and-dependencies.
- How a run behaves: that is the lane correctness-and-concurrency.
- The quality of a test: that is the lane test-discrimination.
