# Development

This document tells you how to build AeroSpork from source, which script does what, how signing and
notarization work, and how to cut a release. `CONTRIBUTING.md` is the short path to a first pull
request. This document is the reference behind it.

If you cannot build locally, compare with the
[builds in GitHub Actions](https://github.com/wbsmolen/aerospork/actions?query=branch%3Amain).

## Toolchain

Use the Xcode that matches your macOS version, and build through Xcode's toolchain.

1. Install Xcode from the [App Store](https://apps.apple.com/us/app/xcode/id497799835). On a beta
   macOS, install the matching Xcode beta. For example, on macOS 27 use Xcode 27.0.
2. Point the build at that Xcode. Use one of these two ways:
   - Select it for the whole machine: `sudo xcode-select -s /Applications/Xcode.app`.
   - Select it for one command: put `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
     before the command.
3. Route the build scripts through `xcrun`. Set `AEROSPORK_SWIFT=xcrun` before each script:

   ```bash
   AEROSPORK_SWIFT=xcrun ./run-tests.sh
   AEROSPORK_SWIFT=xcrun ./build-debug-app.sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test   # Swift tests only
   ```

> [!NOTE]
> Every script sources `script/setup.sh`. Its `swift` function runs `swiftly run swift` when
> [swiftly](https://github.com/swiftlang/swiftly) is installed, and plain `swift` when it is not.
> `AEROSPORK_SWIFT=xcrun` makes it run `xcrun swift` instead. `DEVELOPER_DIR` alone does not
> change that choice.

> [!WARNING]
> If the toolchain does not match the macOS SDK, `swift build` can stop at 0 compiled files and use
> 100% CPU with no error. The swiftly toolchain that `.swift-version` pins does this on a beta macOS,
> on the TOMLKit manifest. If a build makes no progress for a minute, stop it and use the steps above.

CI does the same: `.github/workflows/ci.yml` selects the newest installed Xcode and sets
`AEROSPORK_SWIFT: xcrun`.

## Dependencies

Xcode is the only thing you must install. The scripts download the rest.

`script/install-dep.sh` downloads pinned versions of SwiftFormat, SwiftLint and XcodeGen into
`.deps/`, checks each download against its SHA-256 sum, and does it again only when the pin changes.
`run-tests.sh`, `format.sh` and `generate.sh` call it with the flag they need. It also installs
complgen (with `cargo`) and the Ruby gems (with `bundler`) when a script asks for them. To install
everything at once, run `./script/install-dep.sh --all`.

Some scripts need tools that `install-dep.sh` does not install:

| Tool | Needed by | Install |
|---|---|---|
| Ruby 3 and bundler | `build-docs.sh` (asciidoctor for the site and the man pages) | `rbenv install "$(cat .ruby-version)"`, then `bundler install` |
| Rust (`cargo`), bash, fish | `build-shell-completion.sh` | [rustup](https://www.rust-lang.org/tools/install), then `brew install bash fish` |
| xcbeautify (optional) | `build-release.sh`, for a readable Xcode log | `brew install xcbeautify` |
| swiftly (optional) | `script/setup.sh`, only when `AEROSPORK_SWIFT` is not set | `brew install swiftly` |
| `gh`, `swa`, `az`, `node` | `script/publish-release.sh` | Homebrew or npm |

`script/setup.sh` replaces `PATH` with `.deps/bin:/bin:/usr/bin` so that a build cannot use whatever
else is installed. It links each tool in this table into `.deps/bin` when it finds the tool.

## Scripts

| Script | What it does | Output |
|---|---|---|
| `build-debug.sh` | Builds the app, the CLI and the test target with SwiftPM. Xcode is not involved. | `.debug/aerosporkApp`, `.debug/aerospork` |
| `build-debug-app.sh` | Runs `build-debug.sh`, then assembles and signs a debug `.app` bundle with Sparkle, `Info-Debug.plist`, the default config and the icon. A debug copy needs the bundle to get Accessibility permission. | `.debug/AeroSpork-Debug.app` |
| `launch-debug-app.sh` | Opens the debug bundle. It builds the bundle first if it does not exist. | — |
| `run-debug.sh` | Runs `build-debug.sh`, then runs the bare binary `.debug/aerosporkApp` in the terminal. Arguments go to the binary. | — |
| `run-cli.sh` | Builds if needed, then runs the debug CLI. Arguments go to `aerospork`. | — |
| `run-tests.sh` | The full check. See [What run-tests.sh checks](#what-run-testssh-checks). | — |
| `format.sh` | Runs SwiftFormat, which rewrites files in place, then SwiftLint, which only reports. | — |
| `generate.sh` | Regenerates the `*Generated.swift` files and `aerospork.xcodeproj`. `--ignore-xcodeproj` skips the project. `--all` regenerates everything. | — |
| `build-docs.sh` | Builds the site and the man pages from `docs/`. | `.site/`, `.man/` |
| `build-shell-completion.sh` | Regenerates the completions from `grammar/commands-bnf-grammar.txt`. The output is in git. To try it, run `source ./shell-completion/zsh/_aerospork`. | `shell-completion/` |
| `build-release.sh` | Builds the universal Release configuration with Xcode, signs it, and notarizes it when it can. `--build-version X.Y.Z` sets the version. | `.release/` |
| `install-from-sources.sh` | Runs `build-release.sh`, then installs the result as the `aerospork-dev` Homebrew cask. `--dont-rebuild` skips the build. | — |
| `script/publish-release.sh` | Cuts a release. See [Cutting a release](#cutting-a-release). | — |
| `script/deploy-site.sh` | Deploys `updates-site/` and `.site/` to the hosted site. `publish-release.sh` calls it. | — |
| `script/reset-accessibility-permission-for-debug.sh` | Removes the Accessibility grant of the debug bundle ID, so that macOS asks again. | — |
| `script/clean-project.sh` | Deletes build output and every ignored file except your own state folders, then runs `generate.sh`. | — |

> [!CAUTION]
> `install-from-sources.sh` uninstalls the `aerospork` and `aerospork-dev` Homebrew casks before it
> installs the new build. Your config stays, but the installed app is replaced.

### What run-tests.sh checks

`run-tests.sh` runs these steps in order and stops at the first failure:

1. `build-debug.sh`.
2. `swift test`, which runs `AppBundleTests` and `CommonTests`.
3. Smoke checks of the CLI: `-h`, `--help`, `-v` and `--version`.
4. `swiftformat --lint` and `swiftlint lint`. Neither rewrites a file.
5. `generate.sh --all`. The script records `git status` before step 1 and compares it after step 5.
   If the run changed the tree, the generated files are out of date and the script fails. Local
   work and untracked files do not fail it.

CI runs `run-tests.sh` and then two more checks:

- An unsigned Xcode build of the Release configuration.
- `shellcheck -S warning ./*.sh script/*.sh`.

## Run a debug copy

The debug build has its own bundle ID (`com.wbs.aerospork.debug`), its own config
(`~/.aerospork-debug.toml`), its own CLI socket and its own log subsystem. Your release config is not
touched.

> [!WARNING]
> Quit the installed AeroSpork before you start a debug copy. The single-instance check
> (`initAppBundle.swift`) looks only for its own bundle ID, so the debug copy and the release copy
> both start, and both move the same windows. To recover, quit one of the two.

1. Quit the installed AeroSpork.
2. Run `AEROSPORK_SWIFT=xcrun ./build-debug-app.sh`.
3. Run `./launch-debug-app.sh`.
4. When macOS asks, give Accessibility permission to AeroSpork-Debug. AeroSpork quits after the
   prompt. Run `./launch-debug-app.sh` again.
5. Send commands with `./run-cli.sh <command>`.

When you finish, quit the debug copy and open the installed AeroSpork again.

## Read a debug build's logs

The debug build writes to the `com.wbs.aerospork.debug` subsystem, and its process is `AeroSporkApp`.
For a release build, the subsystem is `com.wbs.aerospork` and the process is `AeroSpork`.

To read the always-on records of the last hour:

```bash
log show --last 1h --predicate 'subsystem == "com.wbs.aerospork.debug"' --style compact
```

To see the verbose trace, set `AEROSPORK_DEBUG_LOG`, restart the debug copy, and stream the log:

1. Run `launchctl setenv AEROSPORK_DEBUG_LOG 1`.
2. Restart the debug copy, so that it gets the variable. Wait for the old process to exit, or `open`
   brings back the old one without the variable:

   ```bash
   killall AeroSporkApp; while pgrep -qx AeroSporkApp; do sleep 0.2; done; open .debug/AeroSpork-Debug.app
   ```

3. Run `log stream --debug --predicate 'subsystem == "com.wbs.aerospork.debug"'`.
4. Reproduce the problem.
5. When you finish, run `launchctl unsetenv AEROSPORK_DEBUG_LOG` and restart the debug copy.

Do not use `open -a AeroSpork` for a debug copy. That command opens the release app next to it.

`debugLog` writes the trace at the `.debug` level, which the unified log does not keep. `log show` cannot
find it later, so start `log stream` before you reproduce the problem. In Console.app, filter by the
subsystem and enable **Action > Include Debug Messages**. `dev-docs/architecture.md`, "Logging",
explains the two channels.

## Code signing

`script/signing-identity.sh` finds signing identities in your keychain. `generate.sh`,
`build-debug-app.sh` and `build-release.sh` use it. No identity is written into the repository.

**The bare SwiftPM binary** (`.debug/aerosporkApp`) is not signed.

**The debug bundle** needs no certificate of your own. `build-debug-app.sh` signs it with a Developer ID
Application identity, or with an Apple Development identity when there is no Developer ID. Set
`AEROSPORK_CODESIGN_IDENTITY` to choose a different identity. Without an identity, it signs
ad hoc. An ad-hoc signature derives the designated requirement from the code hash, so macOS treats
each rebuild as a new app and asks for Accessibility permission again. An Apple Development
certificate keeps the requirement stable across rebuilds.

**A release build** needs an Apple Development certificate at minimum. `build-release.sh` reads
`DEVELOPMENT_TEAM` from the `OU` field of the certificate, not from the `(XXXXXXXXXX)` in its common
name. On an Apple Development certificate, that part of the name is the ID of an API key, so a team
read from the name looks correct and then fails at signing. `build-release.sh` fails before the
universal build when it finds no identity.

**Sparkle** puts a framework with its own XPC helpers in `Contents/Frameworks`. `build-release.sh`
copies it with `cp -R`, which keeps the symlinks of the framework, and signs the nested code deepest
first before it seals the bundle. It then checks that each nested Mach-O file has its own signature.

**The Sparkle keys** `SUFeedURL` and `SUPublicEDKey` come from the `info:` `properties:` block in
`project.yml`. Do not move them to `INFOPLIST_KEY_*` settings. Xcode accepts that prefix only for keys
it knows, and drops other keys with no error. `build-release.sh` checks that both keys are in the
finished bundle.

### Notarization

To distribute a build outside the Mac App Store, you need a **Developer ID Application**
certificate. Two other certificate types do not work:

- **Apple Distribution** is for the Mac App Store. Apple does not notarize it, and Gatekeeper blocks a
  downloaded build signed with it. Xcode lists it directly above the certificate you need.
  `warn_if_only_app_store_distribution` reports this at build time.
- **Apple Development** signs a build that runs on your Mac. Gatekeeper blocks it on every other Mac.

The App Store Connect API cannot create a Developer ID certificate. It answers
`403 This operation can only be performed by the Account Holder`. Create the certificate in Xcode:
**Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application**. Xcode shows that
entry only when the Apple ID is the Account Holder of the team. If the entry is missing, select the
correct account.

Store a notary credential once. An App Store Connect API key is better than an app-specific password,
because one key works for all your projects:

```bash
xcrun notarytool store-credentials aerospork-notary \
  --key <AuthKey_XXXXXXXXXX.p8> --key-id <key id> --issuer <issuer uuid>

export AEROSPORK_NOTARY_PROFILE=aerospork-notary
```

Without a Developer ID certificate or without `AEROSPORK_NOTARY_PROFILE`, `build-release.sh` signs
the build, skips notarization and says so. The local build works. Only distribution is blocked.

To check a finished build, use Apple's preflight check. It is stricter than `codesign -v`:

```bash
syspolicy_check distribution .release/AeroSpork.app
```

## Cutting a release

`script/publish-release.sh` builds, tags and publishes a release, signs the appcast, deploys the site
and updates the Homebrew tap. It needs a Developer ID certificate, a notary profile, and the `gh`,
`swa`, `az` and `node` tools.

1. Write the release notes under `## Unreleased` in `CHANGELOG.md`, then rename that heading to
   `## X.Y.Z (YYYY-MM-DD)`. The script reads that section and stops if it is missing or empty. Put
   each bullet on one line.
   The script converts the notes to HTML for the update dialog, and its converter turns the second
   line of a wrapped bullet into a separate paragraph.
2. Merge the changelog to `main`, and switch to a clean, up-to-date `main`. The script refuses a tree
   with uncommitted or untracked files.
3. Run the script:

   ```bash
   AEROSPORK_NOTARY_PROFILE=aerospork-notary \
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer AEROSPORK_SWIFT=xcrun \
   script/publish-release.sh --build-version X.Y.Z
   ```

4. Commit `updates-site/appcast.xml` exactly as the script leaves it, on a branch, and merge it with
   a pull request titled "Publish X.Y.Z in the appcast".

The script takes these flags:

| Flag | Meaning |
|---|---|
| `--build-version X.Y.Z` | Required. The version to build and tag. |
| `--notes-file <file>` | A Markdown file with the release notes. When you leave it out, the script reads the version's section of `CHANGELOG.md`, and stops before it tags anything if that section is empty. |
| `--cask-git-repo-path <dir>` | A local checkout of the Homebrew tap to update. |

The script makes two archives, and a release needs both:

- `aerospork-vX.Y.Z.zip` is the package that Homebrew and a manual install use.
- `AeroSpork-X.Y.Z.zip` is the Sparkle update archive, with the `.app` at the root. Sparkle refuses
  the other archive.

Before it tags anything, the script runs `run-tests.sh`, builds the release, and checks that both
unpacked archives pass `stapler validate` and `spctl`. After it publishes, it checks that the appcast
signature matches the asset that GitHub serves, and that the hosted site serves the signed feed.

> [!WARNING]
> Never edit `updates-site/appcast.xml` by hand. Builds set `SURequireSignedFeed`, so a client
> refuses a feed whose signature does not match. The failure has no visible error: clients report an
> error for 20 days and offer no update. To change the feed, re-sign it with Sparkle's `sign_update`
> and deploy it again.

## Editors

**Xcode.** Open `Package.swift` with **File > Open**, not `aerospork.xcodeproj`. The SwiftPM project
is lighter. Only the `*release*.sh` scripts use the Xcode project, which `generate.sh` writes from
`project.yml`.

In Xcode, set **Edit Scheme > Options > Console** to **Terminal**. Then macOS asks Terminal for
Accessibility permission once. With the Xcode console, macOS asks again after each rebuild, because
the binary that Xcode runs is not signed.

**Other editors.** Any editor with [sourcekit-lsp](https://github.com/apple/sourcekit-lsp) works.
To attach a debugger without Xcode, use `lldb`.

**Other tools.**

- Accessibility Inspector, which comes with Xcode, shows the accessibility properties of a window.
- [DeskPad](https://github.com/Stengo/DeskPad) and [BetterDisplay 2](https://github.com/waydabber/BetterDisplay)
  emulate more monitors. For DisplayLink behavior, use a real DisplayLink dock.

## When the build goes wrong

- **The build stops at 0 compiled files and uses 100% CPU.** The toolchain does not match the SDK.
  See [Toolchain](#toolchain).
- **macOS asks for Accessibility permission after each rebuild.** The bundle has an ad-hoc signature.
  See [Code signing](#code-signing).
- **Accessibility is granted, but the debug copy does not manage windows.** A stale grant can stay
  after a signature change. Run `script/reset-accessibility-permission-for-debug.sh`, then launch the
  debug copy and grant permission again.
- **`run-tests.sh` says "This run changed the tree".** The generated files are out of date. Run
  `./generate.sh --all` and commit what it changes.
- **Nothing else works.** Run `script/clean-project.sh`.

> [!CAUTION]
> `script/clean-project.sh` refuses to run on a tree with uncommitted changes. It then deletes every
> ignored file except `.local`, `.claude`, `.serena`, `.agents` and `AGENTS.md`, and the Xcode
> DerivedData of the project. Other local files in ignored paths are lost. Commit or move them first.
