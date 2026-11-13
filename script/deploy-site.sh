#!/bin/bash
# Deploys aerospork.app: the updates-site pages plus the built documentation under /docs/.
#
# The docs are assembled at deploy time rather than committed: they are generated HTML that would
# churn on every release, and the appcast history already makes updates-site/ the one generated
# artifact main carries on purpose. `publish-release.sh` calls this after verifying the appcast, so
# the hosted docs always match the newest published build; run it directly for site-only changes.
set -e
cd "$(dirname "$0")/.."
source ./script/setup.sh

./build-docs.sh

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
