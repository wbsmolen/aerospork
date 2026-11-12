---
name: Bug report
about: Something behaves differently from how it is documented
labels: bug
---

<!--
The guide explains each step below:
https://aerospork.app/docs/guide.html#troubleshooting
-->

**What happened, and what you expected instead**

**Steps to reproduce**

1.

**Version and config**

```
$ aerospork --version

$ aerospork config --config-path

```

Attach the config file too. A config path inside the `.app` bundle means that AeroSpork runs the
default config: you have no config, or yours failed to load. `aerospork reload-config --dry-run`
says why.

**Log**

Run this within an hour of the problem, and attach `aerospork.log`:

```
log show --last 1h --predicate 'subsystem == "com.wbs.aerospork"' --style compact > aerospork.log
```

If AeroSpork showed an internal error, attach its report from `~/Library/Logs/com.wbs.aerospork/`.

**Verbose trace**, for a layout or focus problem:

1. Enable tracing, and restart AeroSpork:
   ```
   launchctl setenv AEROSPORK_DEBUG_LOG 1
   killall AeroSpork; while pgrep -qx AeroSpork; do sleep 0.2; done; open -a AeroSpork
   ```
2. Check that the startup record ends in `verbose tracing: on`:
   ```
   log show --last 1h --predicate 'subsystem == "com.wbs.aerospork" AND category == "config"' --style compact
   ```
3. Start the stream. Do not add a `category` filter, because the trace is under category `Debug`:
   ```
   log stream --debug --predicate 'subsystem == "com.wbs.aerospork"' > aerospork-trace.log
   ```
4. Reproduce the problem, then stop the stream with Control-C. Attach `aerospork-trace.log`.
5. Disable tracing, and restart AeroSpork:
   ```
   launchctl unsetenv AEROSPORK_DEBUG_LOG
   killall AeroSpork; while pgrep -qx AeroSpork; do sleep 0.2; done; open -a AeroSpork
   ```

**Monitors**, if the problem involves monitors or docking:

```
$ aerospork list-monitors --format '%{monitor-id} %{monitor-name} %{monitor-fingerprint}'

```

Remove the UUIDs if you do not want to publish them. They identify specific hardware.
