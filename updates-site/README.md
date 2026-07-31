# updates-site

What `https://aerospork.app` serves. Static files, no build step:

| File | Purpose |
|---|---|
| `appcast.xml` | The Sparkle feed every installed copy polls. **The one file that must never break.** |
| `index.html` | Landing page: what AeroSpork is, and how to install it. |
| `privacy.html` | What the app stores, what it sends, and what this host sees. |
| `404.html` | Everything the site has, for anyone who lands on a wrong path. |
| `site.css`, `copy.js` | Shared styles and the copy-to-clipboard button. |
| `icon.png`, `social-preview.png` | The app icon and the link-preview card. |
| `staticwebapp.config.json` | Security headers and the 404 rewrite. |

`icon.png` is byte-identical to
`resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`. Copy it again rather than redrawing
it, so the site cannot drift from the shipping artwork.

## The stylesheet and the script are separate files on purpose

`staticwebapp.config.json` sends `default-src 'none'` with everything else confined to `'self'`,
which is what makes `privacy.html`'s claim — that nothing loads from another host — enforced by the
browser rather than merely promised. An inline `<style>` or `<script>` would need `'unsafe-inline'`
to survive that policy, which would defeat it, or a hash, which breaks silently on the next edit.
So keep them as files.

Verify after any change to the policy, because a CSP failure is invisible until someone loads the
page:

```bash
curl -sI https://aerospork.app/ | grep -i content-security-policy
```

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
