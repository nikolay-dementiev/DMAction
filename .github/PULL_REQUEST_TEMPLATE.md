## What and why

## How it was tested

- [ ] `swift test`
- [ ] `xcodebuild test` on an iOS simulator
- [ ] `Scripts/lint.sh`, `Scripts/check-api.sh` and `Scripts/check-manifest.sh`
- [ ] Every new test fails without the change

## Public API and behaviour

- [ ] The public interface is unchanged, or `Fixtures/API/public-interface.txt` is updated in the same commit
- [ ] Every change that people using the package can notice is in `CHANGELOG.md`

## Compatibility

`ENGINEERING.md` in the repository root defines the classes.

- API impact: none / additive / breaking
- Observable behaviour changes, each one listed, or "none":
- Dependency changes, or "none":
- The discriminator of each new test, the change to the code that it fails on:
- The release it needs: patch / minor / major
