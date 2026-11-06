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

# Resolved before use. `set -e` does not abort on a failure inside `$(...)` when the result is just
# an argument, so a wrong Azure subscription -- the active one is global CLI state and can be changed
# by anything else on the machine -- silently produced an empty token and the deploy failed after the
# release was already public and the tag pushed.
deployment_token="$(az staticwebapp secrets list --name aerospork-updates \
    --resource-group aerospork-updates --query 'properties.apiKey' -o tsv)"
if test -z "$deployment_token"; then
    echo "!!! Could not read the Static Web App deployment token !!!" > /dev/stderr
    echo "The active Azure subscription is '$(az account show --query name -o tsv 2>/dev/null)'." > /dev/stderr
    echo "The appcast lives in 'billy MCT'; switch with: az account set --subscription <id>" > /dev/stderr
    exit 1
fi

# In the environment, not on the command line: any account on the Mac can read argv with `ps`.
SWA_CLI_DEPLOYMENT_TOKEN="$deployment_token" swa deploy "$staging" --env production
rm -rf "$staging"
