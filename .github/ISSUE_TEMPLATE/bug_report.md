---
name: Bug report
about: Something behaves differently from how it is documented
labels: bug
---

**What happened, and what you expected instead**

**Steps to reproduce**

**Version and config path**

```
$ aerospork --version

$ aerospork config --config-path

```

A config path inside the `.app` bundle means no user config is loaded, either because you have none
or because yours failed to parse. `aerospork reload-config --dry-run` says which.

**Log**

```
$ log show --last 15m --predicate 'subsystem == "com.wbs.aerospork"' --style compact

```

Use `com.wbs.aerospork.debug` only if you built a debug build. The `.debug` there names the
build, not the log level. A release build always logs under `com.wbs.aerospork`.

For a focus problem, `AND category == "session"` narrows this to the focus changes AeroSpork made on
its own initiative. It does not record focus that followed a click, so if the jump is not there, say
so: that is useful too.

For a layout or focus problem, add the verbose trace. It is written at debug level, which the
unified log keeps only for a stream that is already running, so start the stream first, then
reproduce. Don't add a `category` filter to it: the trace is under category `Debug`.

```
launchctl setenv AEROSPORK_DEBUG_LOG 1
killall AeroSpork; while pgrep -qx AeroSpork; do sleep 0.2; done; open -a AeroSpork
log stream --debug --predicate 'subsystem == "com.wbs.aerospork"'
```

On 1.2.0 and later, `log show --last 5m --predicate 'subsystem == "com.wbs.aerospork"'` then
contains a line ending `verbose tracing: on`. If it says `off`, the variable did not reach the app
and the trace will be empty. Earlier versions do not write that line.

**Monitors**, if the problem involves more than one:

```
$ aerospork list-monitors --format '%{monitor-fingerprint}'

```

Redact the UUIDs if you would rather not publish them. They identify specific hardware.
