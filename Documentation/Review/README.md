# How a change is reviewed

A change to DMAction is reviewed by a person, by an automated reviewer, or by both. This document
says what each reviewer looks at, how a finding is written, and how findings are put together into
one verdict. It adds no rule to the package. The rules are in
[ENGINEERING.md](../../ENGINEERING.md), [AGENTS.md](../../AGENTS.md) and
[CONTRIBUTING.md](../../CONTRIBUTING.md); a lane applies them and cites the one it applies.

## The lanes

A review is split into lanes, so that each reviewer asks one kind of question and a finding has one
owner. Each lane is a short checklist at `.agents/skills/<lane>/SKILL.md`, with what it checks and
what it ignores. A lane ignores what a CI script already enforces.

| Lane | Folder | The question |
|---|---|---|
| architecture and dependencies | `.agents/skills/architecture-and-dependencies` | does the change keep the package what ENGINEERING.md says it is? |
| correctness and concurrency | `.agents/skills/correctness-and-concurrency` | does a run still behave as ENGINEERING.md says it does? |
| test discrimination | `.agents/skills/test-discrimination` | would the tests catch the defect they claim to catch? |
| public API and documentation | `.agents/skills/public-api-and-documentation` | is the change classified as ENGINEERING.md classifies it, and does everything that people using the package read say so? |

DMAction has no user interface, so it has no accessibility lane. A package with a user interface
adds one.

## The finding line

A finding is one line, with seven fields separated by ` | `:

```text
FILE:LINE | BLOCKING/NON_BLOCKING | lane | CATEGORY | TITLE | WHY | FIX
```

- `FILE:LINE`: the path from the repository root and the first line of the code concerned.
- `BLOCKING` or `NON_BLOCKING`: whether the change must not be merged before the finding is fixed
  or the maintainer decides otherwise.
- `lane`: the lane that found it, by the name of its folder.
- `CATEGORY`: a short upper-case label for the topic of the rule, such as `DELIVERY` or
  `API_CLASS`. It is an open label, not a closed list.
- `TITLE`: the defect in one phrase.
- `WHY`: the rule it breaks, cited as the lane cites it, and the consequence.
- `FIX`: the change that removes it.

A field holds no ` | ` of its own. Two examples, both made up for this document:

```text
Sources/DMAction/Example.swift:42 | BLOCKING | correctness-and-concurrency | DELIVERY | A late completion is delivered | A run delivers one result (ENGINEERING.md, "One delivery") | Ignore a completion after the first result
Tests/DMActionTests/ExampleTests.swift:17 | NON_BLOCKING | test-discrimination | TEST_NAME | The name omits the condition | Names say the subject, the condition and the result (CONTRIBUTING.md, "Names say the subject") | Rename the test
```

## The record

A tool that collects findings keeps each one as a record with these fields:

| Field | What it holds |
|---|---|
| `base_sha` | the commit the change is compared with |
| `head_sha` | the commit that was reviewed |
| `lane` | the lane that found it |
| `rule_id` | the rule it applies: the file and the quoted section or phrase that the lane cites |
| `path` | the file, from the repository root |
| `side` | `base` or `head`: the side of the diff that the lines are on |
| `lines` | the first and the last line concerned |
| `priority` | `P1`, `P2` or `P3`, see below |
| `blocking` | whether the change must not be merged before it is dealt with |
| `api_impact` | `none`, `additive` or `breaking` as ENGINEERING.md defines them, or `unknown` |
| `title` | the defect in one phrase |
| `trigger` | the input, the order of events or the platform that makes the defect happen |
| `consequence` | what happens then |
| `evidence` | what was observed: code read at `head_sha`, a test run, the output of a command |
| `fix` | the change that removes it |
| `verification` | how the fix will be checked |

`blocking` and `priority` are kept apart. Priority is how serious the defect is; blocking is the
decision about merging. A P3 finding can block, for a breaking change that has no migration note,
and a P2 finding can wait, when the maintainer accepts it.

## Putting the findings together

1. Bind every finding to the base and the head commit it was made on. A finding on an older head
   commit is checked again, or dropped.
2. Open the cited code at the head commit. A finding whose file, line or code is not there is
   dropped.
3. Deduplicate by defect, not by line. One defect found by two lanes is one finding that names both
   lanes.
4. Give each finding a priority:
   - **P1**: a crash, a deadlock, a leak, or a break of the public interface that nobody approved.
   - **P2**: a gap in correctness, a test that cannot fail, or an accessibility defect where the
     package has a user interface.
   - **P3**: documentation and style.
5. A change with a blocking finding is not merged until the finding is fixed or the maintainer
   decides otherwise.

## The question that ends a review

A review of a change that is not trivial ends with one question, answered in a sentence or two:

> What kind of defect could still be present outside the paths this review exercised, and which
> lane would have found it?

For DMAction, ask it in this form: could destruction, a late callback or a different platform
still fail outside the exercised path? If the answer names a lane that did not run, run it.

## Remarks of an automated reviewer

A pull request can collect remarks from an automated reviewer. The procedure for handling them, from
the snapshot of the remarks to the reply on every thread, is
[handle-review-remarks](../../.agents/skills/handle-review-remarks/SKILL.md).
