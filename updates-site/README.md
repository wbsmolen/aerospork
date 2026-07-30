# updates-site

What `https://aerospork.app` serves: the Sparkle appcast that installed copies poll, and a plain
page explaining what the host is for. Two static files, no build step.

## Why it is hosted separately

`SUFeedURL` is compiled into the app, so the feed has to stay reachable for the lifetime of every
build that carries it. Serving it from an Azure Static Web App rather than from this repository
means it does not depend on the repository's visibility, its default branch, or GitHub Pages being
configured. What makes the channel safe is `SUPublicEDKey`, not the transport: Sparkle refuses any
update it cannot verify against that key.

## Deploying

```bash
swa deploy updates-site \
  --app-name aerospork-updates \
  --resource-group aerospork-updates \
  --env production
```

## The old hostname must keep answering

Copies of 1.1.0 and earlier ask
`agreeable-glacier-0a845c510.7.azurestaticapps.net` for their feed, because that is what was
compiled into them. It is the Static Web App's own default hostname, so it answers as long as the
app exists and serves the same content as `aerospork.app`. Deleting the Static Web App, or moving
the feed to different infrastructure without leaving a redirect, strands every one of those
installs on the version it already has, silently: Sparkle treats an unreachable feed as nothing to
report.
