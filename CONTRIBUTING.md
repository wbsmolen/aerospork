# Contributing

This document takes you from a clone to an open pull request. `dev-docs/development.md` has the full
reference for the toolchain and the scripts. `dev-docs/architecture.md` has the project rules.

## Before you start

For anything larger than a bug fix, open an issue first. AeroSpork is a fork of AeroSpace, and
feature parity with AeroSpace is not a goal. A change that adds surface area needs a reason other
than "upstream has it".

## Prepare your Mac

1. Install the Xcode that matches your macOS version. On a beta macOS, install the matching Xcode
   beta.
2. Clone the repository.

You need nothing else for the build and the tests. `run-tests.sh` downloads pinned versions of
SwiftFormat, SwiftLint and XcodeGen into `.deps/`. The docs and the shell completions need more
tools. `dev-docs/development.md`, "Dependencies", lists them.

> [!WARNING]
> If the toolchain does not match your macOS SDK, the build can stop at 0 compiled files with no
> error. Put `AEROSPORK_SWIFT=xcrun` before every script, as the commands below do.
> `dev-docs/development.md`, "Toolchain", explains why.

## Build and run a debug copy

The debug copy has its own bundle ID, its own config (`~/.aerospork-debug.toml`) and its own CLI
socket. Your `~/.aerospork.toml` stays as it is.

> [!WARNING]
> Quit the installed AeroSpork before you launch a debug copy. The two copies have different bundle
> IDs, so both run, and both move the same windows. To recover, quit one of them.

1. Quit the installed AeroSpork.
2. Run `AEROSPORK_SWIFT=xcrun ./build-debug-app.sh`.
3. Run `./launch-debug-app.sh`.
4. When macOS asks, give Accessibility permission to AeroSpork-Debug. AeroSpork quits after the
   prompt. Run `./launch-debug-app.sh` again.
5. Put a test config in `~/.aerospork-debug.toml`. Without one, the debug copy uses the bundled
   default config.
6. Send commands with `./run-cli.sh <command>`.
7. When you finish, quit the debug copy and open the installed AeroSpork again.

If macOS asks for Accessibility permission after each rebuild, the bundle has an ad-hoc signature.
See `dev-docs/development.md`, "Code signing".

## Run the checks

1. If you changed Swift, run `./format.sh`. SwiftFormat rewrites the files in place, and SwiftLint
   reports what it finds.
2. Run `AEROSPORK_SWIFT=xcrun ./run-tests.sh`.

`run-tests.sh` builds, runs both test targets, checks the CLI, runs the linters (which do not rewrite
files), and runs `./generate.sh --all`. It fails when the run changes the tree, that is, when the generated files are
out of date. Your uncommitted work and untracked files do not fail it.

CI runs `run-tests.sh` and two more checks:

- An unsigned Xcode build of the Release configuration.
- `shellcheck -S warning ./*.sh script/*.sh`. If you changed a shell script, run `shellcheck` on it.

## Open a pull request

1. Create a branch from `main`. Keep one topic in each pull request.
2. Commit the generated files that `./generate.sh` changes, and the `shell-completion/` files that
   `./build-shell-completion.sh` changes.
3. Push the branch and open a pull request against `main`. The template asks what the change does,
   why, and what a reviewer must look at.
4. Wait for the `test` check. `main` requires it, and accepts a squash or a rebase merge only.

## Rules the tests enforce

Each rule has a reason, and `dev-docs/architecture.md` gives it.

| Rule | Test | Section |
|---|---|---|
| A config section that the user did not edit stays byte for byte the same. A save with no edit changes nothing. | `ConfigTest.testWriterNoOpSaveIsByteIdentical`, `ConfigSafetyWriterFuzzTest` | [The writer invariant](dev-docs/architecture.md#the-writer-invariant) |
| Each shared Settings control lives in `SettingsChrome.swift`. A pane uses it and does not grow its own copy. Status symbols come from `StatusLabel.Kind` and `Banner.Kind`. | `UIChromeConsistencyTest` | [Shared chrome](dev-docs/architecture.md#shared-chrome) |
| Restore the workspace of a window and the monitor of that workspace together. | `WorkspaceMemoryTest` | [Both halves, or neither](dev-docs/architecture.md#both-halves-or-neither) |
| A workspace that the config declares always exists. A workspace that only a binding names stays lazy. | `PersistentWorkspacesTest`, `PerfInvariantsTest` | [Which workspaces exist](dev-docs/architecture.md#which-workspaces-exist) |
| Read the focus of macOS through `syncFocusFromMacOs`. | `InvoluntaryFocusTest` | [Taking focus from macOS](dev-docs/architecture.md#taking-focus-from-macos) |
| Window rules run inside `shieldedFromCancellation`. | `WindowDetectionRetryTest` | [Window rules run to the end](dev-docs/architecture.md#window-rules-run-to-the-end) |
| No session waits for another session. | `RefreshSchedulerTest` | [Refresh and layout](dev-docs/architecture.md#refresh-and-layout) |
| `debugLog` takes an `@autoclosure`, and no hot file has a bare `print`. | `PerfInvariantsTest` | [Logging](dev-docs/architecture.md#logging) |
| Never create an `NSFont` in drawing code. | `PerfInvariantsTest.testDrawingCodeDoesNotAskForFonts` | [Fonts in drawing code](dev-docs/architecture.md#fonts-in-drawing-code) |
| Only `config/upstreamMigration.swift` spells the upstream name. | `BrandingTest` | [Upstream names live in one file](dev-docs/architecture.md#upstream-names-live-in-one-file) |
| Every command has a `docs/aerospork-<name>.adoc` page, and every page has a command. | `CliSurfaceTest` | [Add a command](dev-docs/architecture.md#add-a-command) |
| The two copies of the default config are identical. | `DefaultConfigParityTest` | [Configuration](dev-docs/architecture.md#configuration) |
| Some strings in the design kit match the Swift. | `DesignKitParityTest` | [Design system](dev-docs/architecture.md#design-system) |
| The appcast in the repository is signed, and a build refuses a feed that is not signed. | `ReleaseFeedTest` | [In-app updates](dev-docs/architecture.md#in-app-updates) |

Do not write a performance claim in a doc unless a measurement supports it.
`dev-docs/performance.md` says which numbers exist, and which the available benchmark could not
resolve.

## Change the docs

The docs are AsciiDoc files in `docs/`. Some of them are inputs of the build, and tests check them:

- Each `docs/aerospork-<name>.adoc` page is also a man page, and its `:manpurpose:` line and
  `tag::synopsis` region make the `--help` text of the command. Keep the purpose line on one line,
  with no double quotes and no backslashes. After you change a page, run `./generate.sh` and commit
  the generated files. `CliSurfaceTest` fails on a page with no command, or a command with no page.
- Each ```` ```toml ```` block in `README.md` must parse, and one of them must contain `mod =`
  (`ReadmeExamplesTest`).
- `docs/config-examples/default-config.toml` and `resources/default-config.toml` must stay identical
  (`DefaultConfigParityTest`). Edit both.
- `build-docs.sh` builds the site from `guide.adoc`, `commands.adoc` and `goodies.adoc`. Other docs
  link to the anchor IDs in the guide, so do not rename an anchor. To check the build, run
  `./build-docs.sh` and examine `.site/` and `.man/`.
- Tests cite `dev-docs/performance.md` and `docs/guide.adoc` by path. Do not move them.
- Never edit `updates-site/appcast.xml` by hand. It is signed.

Write the way the product talks. Address the reader as "you", never "we". Explain the consequence,
not the control. When something fails, name the state, then the recovery. Use a colon or a full stop,
not a dash. The design system's `readme.md`, "Content fundamentals", has the full voice
(`.claude/skills/aerospork-design/readme.md`).

## Comment conventions

A `TRADEOFF:` comment marks a deliberate simplification and names its limit. The next reader then
knows that it was a decision, and what would force a change:

```swift
// TRADEOFF: blocking I/O on a dedicated dispatch queue. A short-lived CLI process does not
// need an async event loop; revisit if the server ever multiplexes many clients.
```

Use it for a shortcut that is known to be good enough. Use a plain comment for everything else.

## Report a bug

Use the [bug report template](https://github.com/wbsmolen/aerospork/issues/new?template=bug_report.md).
The guide, "Troubleshooting and bug reports", says which logs to attach and how to capture them. For
a security problem, follow `SECURITY.md` instead.
