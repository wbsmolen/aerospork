#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Cuts a release: build, tag, publish both archives, sign the appcast, update the tap.
#
# It used to open a browser tab and ask you to drag one zip in. That lost two steps every time,
# because a release is not one artifact:
#
#   * `aerospork-v$V.zip`  -- the distribution package Homebrew and manual installers take.
#   * `AeroSpork-$V.zip`   -- the Sparkle update archive, the .app at the archive root. Sparkle
#                             REFUSES the distribution zip ("only .app bundles are supported"), so
#                             without this one, in-app updates are dead.
#
# and the appcast has to name the second one or nothing is offered at all. v1.1.0 shipped without
# `AeroSpork-1.1.0.zip` -- and with the generated cask file uploaded as a release asset by mistake,
# which is what happens when the step is "drag the right file in".

build_version=""
notes_file=""
cask_git_repo_path=""
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --notes-file) notes_file="$2"; shift 2;;
        --cask-git-repo-path) cask_git_repo_path="$2"; shift 2;;
        *) echo "Unknown option $1"; exit 1;;
    esac
done

if test -z "$build_version"; then
    echo "--build-version flag is mandatory" > /dev/stderr
    exit 1
fi
if test -n "$notes_file" && ! test -f "$notes_file"; then
    echo "--notes-file points at a file that does not exist: $notes_file" > /dev/stderr
    exit 1
fi

# Without --notes-file, the notes are this version's CHANGELOG.md section: everything under
# `## X.Y.Z` or `## X.Y.Z (date)` up to the next `## `, leading blank lines dropped. Read here, before
# the twenty-minute build, so a release with no entry stops before anything is tagged.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
if test -z "$notes_file"; then
    notes_file="$work_dir/notes.md"
    awk -v v="$build_version" '
        $1 == "##" { f = ($2 == v); next }
        f && (NF || started) { started = 1; print }
    ' CHANGELOG.md > "$notes_file"
    if ! grep -q '[^[:space:]]' "$notes_file"; then
        echo "CHANGELOG.md has no notes for $build_version. Add a '## $build_version (YYYY-MM-DD)' section, or pass --notes-file." > /dev/stderr
        exit 1
    fi
fi

repo="wbsmolen/aerospork"
changelog_url="https://github.com/$repo/blob/main/CHANGELOG.md"
dist_zip=".release/aerospork-v$build_version.zip"
sparkle_zip=".release/AeroSpork-$build_version.zip"

# `setup.sh` replaces PATH with `.deps/bin:/bin:/usr/bin` so a build cannot pick up whatever happens
# to be installed. These three are linked in there alongside the build tools; the check stays because
# failing here costs nothing and failing after the twenty-minute universal build costs the build.
for tool in gh gcloud python3; do
    command -v "$tool" > /dev/null || {
        echo "Required tool not found: $tool" > /dev/stderr
        echo "Install it, then re-run: script/setup.sh links it into .deps/bin." > /dev/stderr
        exit 1
    }
done

# The appcast host has to be reachable before anything is published: everything after the tag is
# irreversible-ish, and a deploy that cannot authenticate then means a released version that no
# existing install is offered.
if ! curl -sf -o /dev/null \
        -H "Authorization: Bearer $(gcloud auth print-access-token 2> /dev/null)" \
        -H "x-goog-user-project: aerospork-site" \
        https://firebasehosting.googleapis.com/v1beta1/projects/aerospork-site/sites/aerospork-site; then
    echo "Cannot reach the aerospork-site Firebase Hosting site." > /dev/stderr
    echo "Active gcloud account: '$(gcloud config get account 2> /dev/null)'. It must own aerospork-site." > /dev/stderr
    echo "Sign in with: gcloud auth login" > /dev/stderr
    exit 1
fi

# The build embeds `git rev-parse HEAD` and then asserts the binary contains it, so a commit landing
# mid-build fails the release ~20 minutes in. Refuse up front instead.
if test -n "$(git status --porcelain)"; then
    echo "Working tree is dirty. A release must be built from a committed tree." > /dev/stderr
    git status --short > /dev/stderr
    exit 1
fi

# The rest of the pre-flight, so that a bad release stops in seconds and not after the build.
#
# What is on GitHub's main, nothing older and nothing unpushed. --tags also brings a v$V tag someone
# pushed from another clone, which the tag check below must see.
git fetch -q --tags origin main
if test "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)"; then
    echo "HEAD is not origin/main. A release is built from main as it is on GitHub: switch to main and pull." > /dev/stderr
    exit 1
fi

# generate_appcast builds the new feed on updates-site/appcast.xml. If the previous release's appcast PR
# has not merged, that file lacks the newest live item and the new signed feed silently drops it. Equal
# bytes prove that PR merged, and that the version check below reads what clients see.
live_feed="$work_dir/live-appcast.xml"
curl -fsS -o "$live_feed" "https://aerospork.app/appcast.xml?preflight=$(date +%s)" ||
    { echo "Could not fetch the live appcast to compare it with updates-site/appcast.xml." > /dev/stderr; exit 1; }
if ! cmp -s "$live_feed" updates-site/appcast.xml; then
    echo "updates-site/appcast.xml is not the live appcast. Merge the PR that publishes the previous release in the appcast, pull, and run again." > /dev/stderr
    exit 1
fi

# project.yml: the version must never go backwards, or Sparkle never offers the build.
feed_version="$({ grep -o '<sparkle:version>[^<]*</sparkle:version>' updates-site/appcast.xml || true; } | sed 's/<[^>]*>//g' | sort -V | tail -1)"
if test -z "$feed_version"; then
    echo "No <sparkle:version> in updates-site/appcast.xml, so cannot tell whether $build_version is new." > /dev/stderr
    exit 1
fi
if test "$build_version" = "$feed_version" || test "$(printf '%s\n%s\n' "$feed_version" "$build_version" | sort -V | tail -1)" != "$build_version"; then
    echo "--build-version $build_version is not above $feed_version, the newest version in the appcast." > /dev/stderr
    exit 1
fi

# A tag at HEAD is a re-run after a step before the site deploy failed, so the tag step reuses it and
# the release step re-uploads the archives. Once the deploy landed the live feed names this version and
# the checks above refuse a re-run, which is right: only the appcast PR is left. Anywhere else, the
# version was already cut from other code.
tag_exists=false
if tagged_commit="$(git rev-parse -q --verify "refs/tags/v$build_version^{commit}")"; then
    if test "$tagged_commit" != "$(git rev-parse HEAD)"; then
        echo "Tag v$build_version already exists and points at $tagged_commit, not HEAD." > /dev/stderr
        exit 1
    fi
    tag_exists=true
fi

./run-tests.sh
./build-release.sh --build-version "$build_version"

for artifact in "$dist_zip" "$sparkle_zip"; do
    test -f "$artifact" || { echo "Missing build artifact: $artifact" > /dev/stderr; exit 1; }
done

# build-release.sh skips notarization on purpose when it has no Developer ID certificate or notary
# profile, so that a local build still works: it warns and exits 0. So nothing stopped a release
# Gatekeeper blocks on every other Mac. Everything after this block is outward-facing.
#
# Both archives, unpacked as they will be downloaded: the ticket that counts is the one that survived
# zipping, not the one on .release/AeroSpork.app. /usr/sbin/spctl in full because setup.sh's PATH has
# no /usr/sbin.
notary_check_dir="$(mktemp -d)"
ditto -x -k "$dist_zip" "$notary_check_dir/dist"
ditto -x -k "$sparkle_zip" "$notary_check_dir/sparkle"
for app in "$notary_check_dir/dist/aerospork-v$build_version/AeroSpork.app" "$notary_check_dir/sparkle/AeroSpork.app"; do
    if ! xcrun stapler validate "$app" || ! /usr/sbin/spctl --assess --type execute --verbose "$app"; then
        echo "!!! This build is not notarized. Nothing has been tagged or published. !!!" > /dev/stderr
        echo "It needs a Developer ID Application certificate and AEROSPORK_NOTARY_PROFILE; see build-release.sh." > /dev/stderr
        exit 1
    fi
done
rm -rf "$notary_check_dir"

if ! "$tag_exists"; then
    git tag -a "v$build_version" -m "v$build_version"
fi
# Also when the tag existed: a no-op if it is on GitHub, and the missing step if the last push failed.
git push origin "v$build_version"

# A re-run rebuilt and re-signed both archives, so a release left by the failed run gets the new files:
# the appcast below signs these bytes, and a stale download would fail its signature.
if gh release view "v$build_version" --repo "$repo" > /dev/null 2>&1; then
    gh release upload "v$build_version" --repo "$repo" --clobber "$dist_zip" "$sparkle_zip"
else
    gh release create "v$build_version" --repo "$repo" --title "AeroSpork $build_version" \
        --notes-file "$notes_file" "$dist_zip" "$sparkle_zip"
fi

##################
### THE APPCAST ##
##################

# Generated from the Sparkle archive, never the distribution zip. `generate_appcast` re-uses an
# appcast already present in the directory, so seeding it with the live one keeps the channel
# metadata and the older items.
appcast_workdir="$work_dir/appcast"
mkdir "$appcast_workdir"
cp "$sparkle_zip" "$appcast_workdir/"
cp updates-site/appcast.xml "$appcast_workdir/appcast.xml"

# Release notes, so the update dialog is not blank -- without them Sparkle shows an empty pane while
# perfectly good notes sit on the GitHub release doing nothing.
#
# HTML, not Markdown: see the comment at the top of the converter.
notes_html="$appcast_workdir/AeroSpork-$build_version.html"
python3 script/release-notes-html.py "$notes_file" > "$notes_html"
# Sparkle's update dialog shows the notes of the newest item only, so someone who skipped versions
# would never see the upgrade notes in between. Point them at the whole history.
echo "<p><a href=\"$changelog_url\">Changes in earlier versions</a></p>" >> "$notes_html"

sparkle_bin="$(find .build/artifacts -type d -name bin -path '*sparkle*' | head -1)"
test -n "$sparkle_bin" || { echo "Sparkle tools not found; run a build first" > /dev/stderr; exit 1; }

"$sparkle_bin/generate_appcast" \
    --embed-release-notes \
    --full-release-notes-url "$changelog_url" \
    --download-url-prefix "https://github.com/$repo/releases/download/v$build_version/" \
    --link "https://github.com/$repo" \
    "$appcast_workdir"
cp "$appcast_workdir/appcast.xml" updates-site/appcast.xml

# Explicitly, and checked. generate_appcast writes the feed unsigned, silently, if it has no key, and a
# client that requires a signature then offers nothing at all.
"$sparkle_bin/sign_update" updates-site/appcast.xml
if ! "$sparkle_bin/sign_update" --verify updates-site/appcast.xml > /dev/null 2>&1; then
    echo "!!! The appcast's own signature does not verify !!!" > /dev/stderr
    exit 1
fi

# The signature has to verify against the asset GitHub actually serves, not the local copy. A wrong
# enclosure URL, a re-zipped artifact or a mismatched key all show up here and nowhere else.
signature="$(grep -m1 -o 'edSignature="[^"]*"' updates-site/appcast.xml | sed 's/edSignature="//; s/"$//')"
published="$appcast_workdir/published.zip"
curl -fsSL -o "$published" "https://github.com/$repo/releases/download/v$build_version/AeroSpork-$build_version.zip"
if ! "$sparkle_bin/sign_update" --verify "$published" "$signature" > /dev/null 2>&1; then
    echo "!!! The appcast signature does not verify against the published asset !!!" > /dev/stderr
    exit 1
fi

# Deploys the appcast together with the site pages and the built docs under /docs/, so the hosted
# documentation always matches the newest published build. It authenticates with your gcloud login.
./script/deploy-site.sh

# What clients get has to be what was signed. A single changed byte between here and them, from a CDN
# rewriting XML or a stale deploy, and every copy that requires a signature stops offering updates.
served_feed="$appcast_workdir/served-appcast.xml"
feed_is_served=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -fsS -o "$served_feed" "https://aerospork.app/appcast.xml?published=$build_version" || true
    if cmp -s "$served_feed" updates-site/appcast.xml; then feed_is_served=true; break; fi
    sleep 15
done
if ! "$feed_is_served" || ! "$sparkle_bin/sign_update" --verify "$served_feed" > /dev/null 2>&1; then
    echo "!!! The feed being served is not the signed one. Clients that require a signature offer no updates until it is !!!" > /dev/stderr
    exit 1
fi

################
### THE CASK ###
################

./script/build-brew-cask.sh \
    --cask-name aerospork \
    --zip-uri "https://github.com/$repo/releases/download/v$build_version/aerospork-v$build_version.zip" \
    --build-version "$build_version"

if test -n "$cask_git_repo_path"; then
    if ! test -d "$cask_git_repo_path"; then
        echo "--cask-git-repo-path points at a directory that does not exist" > /dev/stderr
        exit 1
    fi
    cp .release/aerospork.rb "$cask_git_repo_path/Casks/aerospork.rb"
    echo "Cask copied into $cask_git_repo_path -- commit and push it there."
else
    # No local clone needed for a one-file change.
    gh api -X PUT "repos/wbsmolen/homebrew-tap/contents/Casks/aerospork.rb" \
        -f message="aerospork $build_version" \
        -f content="$(base64 -i .release/aerospork.rb | tr -d '\n')" \
        -f sha="$(gh api repos/wbsmolen/homebrew-tap/contents/Casks/aerospork.rb -q .sha)" > /dev/null
    echo "Tap updated to $build_version."
fi

echo
echo "Published v$build_version. Remaining by hand:"
echo "  * commit updates-site/appcast.xml"
