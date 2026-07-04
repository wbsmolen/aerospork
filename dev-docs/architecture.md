# Architecture

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## High level project infrastructure overview

- `../Sources`.
  The majority of aerospork source code. Managed by SPM `../Package.swift`
- `../Sources/AppBundle/`.
  aerospork.app server. Technically, it's a SPM library that is exposed to the `aerosporkApp` executable target.
- `../Sources/aerosporkApp/`.
  Thin app entry point (`@main`). SPM can't build a macOS App Bundle, so the release build is produced via the
  generated Xcode project. The Xcode project model lives in `../aerospork.xcodeproj/` and is generated from the
  `../project.yml` "skeleton" by `./generate.sh`. Keep as much code as possible in the `AppBundle` library.
- `../Sources/Cli/`.
  CLI client. CLI client is built purely using SPM, no Xcode involved (phew!)
- `../Sources/Common/`.
  Shared code between server and client (command-line args parsing, util functions, and the native Unix-socket IPC).
- `../Sources/AppBundleTests/`.
  Tests
- `../docs/`.
  Documentation sources for site and man pages in Asciidoc format https://asciidoc.org/

## client/server interaction

`aerospork` CLI binary is client. `aerospork.app` is server. Client and server talk to each other via predefined UNIX file.

Each time you run a CLI command:
1. Args are parsed by the client, args parsing errors are reported if any. Help is shown if `-h`/`--help` is passed.
1. If args are parsed successfully, the args are send to the server
1. Server parses the args once again, and runs the command
1. Server returns stdout, stderr, and exit code to the client
1. Client shows stdout, stderr, and ends the process with the requested exit code

## Commands subsystem

todo

../Sources/AppBundle/command/
../Sources/Common/cmdArgs/

Command checklist:
- [ ] Documentation in `../docs/aerospork-*` and `../docs/commands.adoc`
  - [ ] Check that site looks alright `./.site/commands.html`
  - [ ] Check that man page looks alright `./.man`
- [ ] Do `--window-id` and/or `--workspace` flags make sense for the command?
- [ ] Shell completion `../grammar/commands-bnf-grammar.txt`

## TOML Config parse subsystem

todo

../Sources/AppBundle/config/

## Tree Model subsystem

todo

../Sources/AppBundle/tree/

## Layout subsystem

todo

../Sources/AppBundle/layout/
