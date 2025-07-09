 <img src="./resources/Assets.xcassets/AppIcon.appiconset/icon.png" width="40%" height="40%" align="right">

# AeroSpork Beta [![Build](https://github.com/wbsmolen/aerospork/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/wbsmolen/aerospork/actions/workflows/build.yml)

AeroSpork is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) by nikitabobko - an i3-like tiling window manager for macOS

## Credits

**Original AeroSpace Project**: [https://github.com/nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)  
**Original Author**: [nikitabobko](https://github.com/nikitabobko)

AeroSpork maintains the core functionality of AeroSpace with minor modifications. All credit for the core window management functionality goes to the original AeroSpace project and its contributors

Videos:
- [YouTube 91 sec Demo](https://www.youtube.com/watch?v=UOl7ErqWbrk)
- [YouTube Guide by Josean Martinez](https://www.youtube.com/watch?v=-FoWClVHG5g)

Docs:
- [AeroSpork Guide](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc)
- [AeroSpork Commands](https://github.com/wbsmolen/aerospork/blob/main/docs/commands.adoc)
- [AeroSpork Goodies](https://github.com/wbsmolen/aerospork/blob/main/docs/goodies.adoc)

## Project status

Public Beta. AeroSpace can be used as a daily driver, but expect breaking changes until 1.0 is reached.

What stops us from 1.0 release:
- [x] Performance improvements (original issue #131) Performance. Implement thread-per-application to circumvent macOS blocking AX API, plus comprehensive optimizations achieving 26-53% performance improvements.
- [ ] Big refactoring (original issue #1215) _Big refactoring_. Rewrite mutable double-linked core tree data structure to immutable single-linked persistent tree.
  Important for: stability and potential performance
  - [ ] Fix stability issue with windows jumping to focused workspace (original issue #1216) The big refactoring will help us to fix stability issue that windows may randomly jump to the focused workspace
  - [ ] Support macOS native tabs (original issue #68) The big refactoring will help us to support macOS native tabs
- [ ] Implement shell-like combinators (original issue #278) Implement shell-like combinators.
  Ignore a lot of crazy fuss in the issue,
  We are most probably going with the minimal approach to only introduce common shell-combinators: `||`, `&&`, `;` and `eval` command to send multiple commands in one go.
- [ ] Investigate CGEvent.tapCreate API for global hotkeys (original issue #1012) Investigate a possibility to use `CGEvent.tapCreate` API for global hotkeys
  - [ ] Distinguish left and right modifiers (original issue #28) Maybe it will allow to distinguish left and right modifiers. Maybe not

Big and important issues which will go after 1.0 release:
- [ ] Sticky windows (original issue #2)
- [ ] Dynamic TWM (original issue #260)

## Key features

- Tiling window manager based on a [tree paradigm](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#tree)
- [i3](https://i3wm.org/) inspired
- Fast workspaces switching without animations and without the necessity to disable SIP
- AeroSpork employs its [own emulation of virtual workspaces](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#emulation-of-virtual-workspaces) instead of relying on native macOS Spaces due to [their considerable limitations](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#emulation-of-virtual-workspaces)
- Plain text configuration (dotfiles friendly). See: [default-config.toml](https://github.com/wbsmolen/aerospork/blob/main/docs/config-examples/default-config.toml)
- CLI first (manpages and shell completion included)
- Doesn't require disabling SIP (System Integrity Protection)
- [Proper multi-monitor support](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#multiple-monitors) (i3-like paradigm)
- [Monitor fingerprinting](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#monitor-fingerprinting) for persistent workspace assignment in docking setups)

## Installation

Install via [Homebrew](https://brew.sh/) to get autoupdates (Preferred)

```
# Installation from source - see installation section in docs/guide.adoc
```

In multi-monitor setup please make sure that monitors [are properly arranged](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#proper-monitor-arrangement).

Other installation options: See [installation guide](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#installation)

> [!NOTE]
> By using AeroSpork, you acknowledge that it's not [notarized](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
>
> Notarization is a "security" feature by Apple.
> You send binaries to Apple, and they either approve them or not.
> In reality, notarization is about building binaries the way Apple likes it.
>
> I don't have anything against notarization as a concept.
> I specifically don't like the way Apple does notarization.
> I don't have time to deal with Apple.
>
> When installed via Homebrew, the installation script is configured to
> automatically delete `com.apple.quarantine` attribute, that's why the app should work out of the box, without any warnings that
> "Apple cannot check AeroSpork for malicious software"

## Community, discussions, issues

AeroSpork project doesn't accept Issues directly - we ask you to create a [Discussion](https://github.com/wbsmolen/aerospork/discussions) first.
Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for more details.

Community discussions happen at GitHub Discussions.
There you can discuss bugs, propose new features, ask your questions, show off your setup, or just chat.

There are 7 channels:
-   [#all](https://github.com/wbsmolen/aerospork/discussions).
    [RSS](https://github.com/wbsmolen/aerospork/discussions.atom?discussions_q=sort%3Adate_created).
    Feed with all discussions.
-   [#announcements](https://github.com/wbsmolen/aerospork/discussions/categories/announcements).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/announcements.atom?discussions_q=category%3Aannouncements+sort%3Adate_created).
    Only maintainers can post here.
    Highly moderated traffic.
-   [#announcements-releases](https://github.com/wbsmolen/aerospork/discussions/categories/announcements-releases).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/announcements-releases.atom?discussions_q=category%3Aannouncements-releases+sort%3Adate_created).
    Announcements about non-patch releases.
    Only maintainers can post here.
-   [#feature-ideas](https://github.com/wbsmolen/aerospork/discussions/categories/feature-ideas).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/feature-ideas.atom?discussions_q=category%3Afeature-ideas+sort%3Adate_created).
-   [#general](https://github.com/wbsmolen/aerospork/discussions/categories/general).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/general.atom?discussions_q=sort%3Adate_created+category%3Ageneral).
-   [#potential-bugs](https://github.com/wbsmolen/aerospork/discussions/categories/potential-bugs).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/potential-bugs.atom?discussions_q=category%3Apotential-bugs+sort%3Adate_created).
    If you think that you have encountered a bug, you can discuss your bugs here.
-   [#questions-and-answers](https://github.com/wbsmolen/aerospork/discussions/categories/questions-and-answers).
    [RSS](https://github.com/wbsmolen/aerospork/discussions/categories/questions-and-answers.atom?discussions_q=category%3Aquestions-and-answers+sort%3Adate_created).
    Everyone is welcome to ask questions.
    Everyone is encouraged to answer other people's questions.

## Development

A notes on how to setup the project, build it, how to run the tests, etc. can be found here: [dev-docs/development.md](./dev-docs/development.md)

## Project values

**Values**
- AeroSpork is targeted at advanced users and developers
- Keyboard centric
- Breaking changes (configuration files, CLI, behavior) are avoided as much as possible, but it must not let the software stagnate.
  Thus breaking changes can happen, but with careful considerations and helpful message.
  [Semver](https://semver.org/) major version is bumped in case of a breaking change (It's all guaranteed once AeroSpork reaches 1.0 version, until then breaking changes just happen)
- AeroSpork doesn't use GUI, unless necessarily
  - AeroSpork will never provide a GUI for configuration.
    For advanced users, it's easier to edit a configuration file in text editor rather than navigating through checkboxes in GUI.
  - Status menu icon is ok, because visual feedback is needed
- Provide _practical_ features. Fancy appearance features are not _practical_ (e.g. window borders, transparency, animations, etc.)
- "dark magic" (aka "private APIs", "code injections", etc.) must be avoided as much as possible
  - Right now, AeroSpork uses only a single private API to get window ID of accessibility object `_AXUIElementGetWindow`.
    Everything else is [macOS public accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement_h).
  - AeroSpace will never require you to disable SIP (System Integrity Protection).
  - The goal is to make AeroSpace easily maintainable, and resistant to macOS updates.

**Non Values**
- Play nicely with existing macOS features.
  If limitations are imposed then AeroSpace won't play nicely with existing macOS features
  (For example, AeroSpace doesn't acknowledge the existence of macOS Spaces, and it uses [emulation of its own workspaces](https://github.com/wbsmolen/aerospork/blob/main/docs/guide.adoc#emulation-of-virtual-workspaces))
- Ricing.
  AeroSpace provides only a very minimal support for ricing - gaps and a few callbacks for integrations with bars.
  The current maintainer doesn't care about ricing.
  Ricing issues are not a priority, and they are mostly ignored.
  The ricing stance can change only with the appearance of more maintainers.

## Acknowledgments

This project is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) originally created by Nikita Bobko. The original project was licensed under the MIT License.

## Tip of the day

```bash
defaults write -g NSWindowShouldDragOnGesture -bool true
```

Now, you can move windows by holding `ctrl`+`cmd` and dragging any part of the window (not necessarily the window title)

Source: [reddit](https://www.reddit.com/r/MacOS/comments/k6hiwk/keyboard_modifier_to_simplify_click_drag_of/)

## Related projects

- [Amethyst](https://github.com/ianyh/Amethyst)
- [yabai](https://github.com/koekeishiya/yabai)
