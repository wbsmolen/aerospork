# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this
repository. The report then stays private until there is a fix. Do not open a public issue for a
security problem.

If private reporting is unavailable, open an issue that says only that you have a security report
and asks for a contact address. Do not include details in it.

## What this app can do, so you know what a bug here is worth

AeroSpork needs Accessibility permission, which is broad: with it, the app can read and change the
windows of every other running application. It is not sandboxed, because the Accessibility APIs do
not work in a sandbox. Anything that lets an attacker influence what AeroSpork runs is therefore
serious, and the config file is the most likely route:

- `exec-and-forget` and the `after-startup-command` / focus callbacks run shell commands through
  `/bin/bash -c`. A config file is executable content. Treat it like a shell script, not like a
  settings file.
- Window rules act on `AXTitle` and the bundle ID. Any app that can name its own window controls
  both. A rule that runs a command on a title match is a way for another application to trigger it.
- The IPC socket is `AF_UNIX` at `/tmp/<bundle-id>-<user>.sock`, so it is reachable by any process
  running as the same user. Both ends check with `getpeereid` that the other runs as the same user
  and hang up if it does not. There is no other authentication, and the app runs the commands that
  arrive on it. This is the same trust model as the config file: same-user processes are already
  trusted.
- AeroSpork remembers window placement across a restart in
  `~/Library/Caches/<bundle-id>/workspace-memory.json`, mode `0600`. It reads that file at startup
  and acts on it. A same-user process can edit the file and move windows to a workspace you did not
  choose. That is the same trust boundary as the socket and the config. The file records window IDs,
  workspace names, bundle IDs, monitor fingerprints and the tiling tree of each workspace, and
  nothing else. AeroSpork discards a
  file from another WindowServer session, and an entry that names a different app for a window ID.

The CLI refuses `exec-and-forget`, and that refusal is UX, not a security boundary. It keeps a shell
from looking like a window manager subcommand. A process that can reach the socket can already write
the config, which runs `exec-and-forget` on the next reload, and as the same user it could run the
shell itself anyway. Do not rely on it to contain anything. A way around it is not a vulnerability.

Reports about any of the above are in scope. So are signing, notarization and update-channel
problems. Sparkle checks each update against the EdDSA public key in the app's Info.plist before it
unpacks the update, and a way to make it accept an update signed by another key would be a serious
finding. The same key signs the feed, and a build refuses a feed that is not signed. Thus a party that
can serve the feed still cannot offer an old version.

## Out of scope

- Needing Accessibility permission at all. That is what a window manager is.
- A same-user process driving the CLI socket, or editing your config. Both are inherent to the trust
  model above.
- The private `_AXUIElementGetWindow` symbol. It is a documented trade, noted in the README.

## Supported versions

The latest release. This is a young fork with a single maintainer, so there are no backported
security branches.
