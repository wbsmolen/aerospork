# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this
repository. That keeps the report private until there is a fix. Please do not open a public issue
for a security problem.

If private reporting is unavailable, open an issue that says only that you have a security report
and asks for a contact address. Do not include details in it.

## What this app can do, so you know what a bug here is worth

AeroSpork needs Accessibility permission, which is broad: with it, the app can read and change the
windows of every other running application. It is not sandboxed, because the Accessibility APIs do
not work in a sandbox. Anything that lets an attacker influence what AeroSpork executes is therefore
serious, and the config file is the most likely route:

- `exec-and-forget` and the `after-startup-command` / focus callbacks run shell commands through
  `/bin/bash -c`. A config file is executable content, and should be treated like a shell script
  rather than like a settings file.
- Window rules act on `AXTitle` and bundle id, both of which are attacker-influenceable by any app
  that can name its own window. A rule that runs a command on a title match is a way for another
  application to trigger it.
- The IPC socket is `AF_UNIX` at `/tmp/<bundle-id>-<user>.sock`, so it is reachable by any process
  running as the same user. There is no authentication beyond filesystem permissions, and commands
  arriving on it are executed. This is the same trust model as the config file: same-user processes
  are already trusted.
- Window placement is remembered across a restart in
  `~/Library/Caches/<bundle-id>/workspace-memory.json`, mode `0600`, and it is read at startup and
  acted on. A same-user process can edit it and move windows to a workspace you did not choose --
  the same trust boundary as the socket and the config. It records bundle ids and monitor UUIDs, and
  nothing else; a file from another window-server session, or one naming a different app for an id,
  is discarded rather than applied.

Reports about any of the above are in scope. So are signing, notarization and update-channel
problems: updates are verified against an EdDSA public key compiled into the app, and a way to make
it accept an update signed by another key would be a serious finding.

## Out of scope

- Needing Accessibility permission at all. That is what a window manager is.
- A same-user process driving the CLI socket, or editing your config. Both are inherent to the trust
  model above.
- The private `_AXUIElementGetWindow` symbol. It is a documented trade, noted in the README.

## Supported versions

The latest release. This is a young fork with a single maintainer, so there are no backported
security branches.
