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
  running as the same user. Both ends check with `getpeereid` that the other runs as the same user
  and hang up if it does not, but there is no other authentication, and commands arriving on it are
  executed. This is the same trust model as the config file: same-user processes are already trusted.
- Window placement is remembered across a restart in
  `~/Library/Caches/<bundle-id>/workspace-memory.json`, mode `0600`, and it is read at startup and
  acted on. A same-user process can edit it and move windows to a workspace you did not choose --
  the same trust boundary as the socket and the config. It records bundle ids and monitor UUIDs, and
  nothing else; a file from another window-server session, or one naming a different app for an id,
  is discarded rather than applied.

The CLI refuses `exec-and-forget`, and that refusal is UX, not a security boundary. It keeps a shell
from looking like a window manager subcommand. A process that can reach the socket can already write
the config, which runs `exec-and-forget` on the next reload, and as the same user it could run the
shell itself anyway. Do not rely on it to contain anything; getting around it is not a vulnerability.

Reports about any of the above are in scope. So are signing, notarization and update-channel
problems: updates are verified against an EdDSA public key in the app's Info.plist before they are
unpacked, and a way to make it accept an update signed by another key would be a serious finding. The
feed itself is not signed; it is served over HTTPS, and it can only offer what that key has signed.

## Out of scope

- Needing Accessibility permission at all. That is what a window manager is.
- A same-user process driving the CLI socket, or editing your config. Both are inherent to the trust
  model above.
- The private `_AXUIElementGetWindow` symbol. It is a documented trade, noted in the README.

## Supported versions

The latest release. This is a young fork with a single maintainer, so there are no backported
security branches.
