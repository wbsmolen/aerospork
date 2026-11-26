#!/bin/bash
# Deploys aerospork.app: the updates-site pages plus the built documentation under /docs/.
#
# The docs are assembled at deploy time rather than committed: they are generated HTML that would
# churn on every release, and the appcast history already makes updates-site/ the one generated
# artifact main carries on purpose. `publish-release.sh` calls this after verifying the appcast, so
# the hosted docs always match the newest published build; run it directly for site-only changes.
# Either way it refuses an appcast older than the live one, or one whose signature does not verify.
set -e
cd "$(dirname "$0")/.."
source ./script/setup.sh

./build-docs.sh

# Refuse a feed that would roll clients back or that does not verify. Both fail silently otherwise:
# after a release the new appcast is committed by a later PR, so a site deploy from a tree without it
# serves the previous, still validly signed feed and Sparkle quietly stops offering the new build;
# and a feed whose signature is wrong makes every client offer nothing, with no error, for 20 days.
highest_version() {
    { grep -o '<sparkle:version>[^<]*</sparkle:version>' "$1" || true; } | sed 's/<[^>]*>//g' | sort -V | tail -1
}
live_feed="$(mktemp)"
trap 'rm -f "$live_feed"' EXIT
live_status="$(curl -sS -o "$live_feed" -w '%{http_code}' "https://aerospork.app/appcast.xml?deploy=$(date +%s)")" ||
    { echo "Could not fetch the live appcast, so cannot tell whether this deploy rolls it back. Nothing was deployed." > /dev/stderr; exit 1; }
local_version="$(highest_version updates-site/appcast.xml)"
case "$live_status" in
    404) ;; # Nothing is live yet: a first deploy.
    200)
        live_version="$(highest_version "$live_feed")"
        if test -z "$local_version" || test -z "$live_version"; then
            echo "No <sparkle:version> in the local or the live appcast. Nothing was deployed." > /dev/stderr
            exit 1
        fi
        if test "$(printf '%s\n%s\n' "$live_version" "$local_version" | sort -V | tail -1)" != "$local_version"; then
            echo "The live appcast offers $live_version, but updates-site/appcast.xml offers only $local_version." > /dev/stderr
            echo "Deploying would stop clients being offered $live_version. Merge the PR that publishes it in the appcast, then deploy. Nothing was deployed." > /dev/stderr
            exit 1
        fi
        ;;
    *) echo "The live appcast answered HTTP $live_status. Nothing was deployed." > /dev/stderr; exit 1 ;;
esac

sparkle_bin="$({ find .build/artifacts -type d -name bin -path '*sparkle*' 2> /dev/null || true; } | head -1)"
test -n "$sparkle_bin" || { echo "Sparkle's sign_update not found; run a build first. Nothing was deployed." > /dev/stderr; exit 1; }
if ! "$sparkle_bin/sign_update" --verify updates-site/appcast.xml > /dev/null 2>&1; then
    echo "updates-site/appcast.xml does not verify, and clients that require a signature would offer no updates. Re-sign it with sign_update. Nothing was deployed." > /dev/stderr
    exit 1
fi

staging=".site-deploy"
rm -rf "$staging"
mkdir "$staging"
cp -R updates-site/. "$staging"
mkdir "$staging/docs"
cp -R .site/. "$staging/docs"

# The checked-in docs/index.html is a redirect to GitHub, for anyone opening a local .site build
# in a browser. On the hosted site the guide IS the home.
cat > "$staging/docs/index.html" << 'HTML'
<!doctype html>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=/docs/guide.html">
<title>AeroSpork documentation</title>
<a href="/docs/guide.html">AeroSpork guide</a>
HTML

# Firebase Hosting, project aerospork-site. firebase.json holds the headers; 404.html is served for
# any missing path without configuration. The deploy authenticates with your gcloud login.
python3 script/firebase-deploy.py . aerospork-site
rm -rf "$staging"
