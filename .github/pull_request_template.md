## What

<!-- What the change does, in one or two sentences. Name the user-visible effect first. -->

## Why

<!-- The problem it solves. Link the issue if there is one. -->

## What to look at

<!-- The part a reviewer must read closely: a risky edit, a decision you made, a rule from
     dev-docs/architecture.md that the change touches. -->

## Checks

- [ ] `AEROSPORK_SWIFT=xcrun ./run-tests.sh` passes.
- [ ] I ran `./format.sh` if I changed Swift.
- [ ] I committed the files that `./generate.sh` or `./build-shell-completion.sh` changed.
- [ ] If I changed a command or a doc page, I ran `./build-docs.sh` and examined the result.
- [ ] If I changed behavior that a user sees, I added a bullet to `CHANGELOG.md`, on one line.
