# updates-site

What `https://aerospork.app` serves. Static files, no build step. The site runs on Firebase
Hosting, project `aerospork-site`, and `firebase.json` at the repository root sets its headers.
Firebase serves `404.html` for any path that does not exist.

| File | Purpose |
|---|---|
| `appcast.xml` | The Sparkle feed every installed copy polls. **The one file that must never break.** |
| `index.html` | Landing page: what AeroSpork is, and how to install it. |
| `privacy.html` | What the app stores, what it sends, and what this host sees. |
| `404.html` | Everything the site has, for anyone who lands on a wrong path. |
| `site.css`, `copy.js` | Shared styles and the copy-to-clipboard button. |
| `icon.png`, `social-preview.png` | The app icon and the link-preview card. |

`icon.png` is byte-identical to
`resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`. Copy it again rather than redrawing
it, so the site cannot drift from the shipping artwork.

## The stylesheet and the script are separate files on purpose

`firebase.json` sends `default-src 'none'` with everything else confined to `'self'`,
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
build that carries it. Serving it from Firebase Hosting rather than from this repository means it
does not depend on the repository's visibility, its default branch, or GitHub Pages being
configured. GitHub Pages also cannot set response headers, so it could not send the CSP above. What makes the channel safe is `SUPublicEDKey`, not the transport: Sparkle refuses any
update it cannot verify against that key.

## Deploying

```bash
script/deploy-site.sh
```

The script deploys with `script/firebase-deploy.py`, which uses your `gcloud` login. Sign in with
`gcloud auth login` as an owner of the `aerospork-site` project.

Do not deploy this directory alone: the live site also serves the built documentation under
`/docs/`, which the script assembles from `build-docs.sh` output at deploy time (generated HTML is
deliberately not committed). Deploying this directory alone would republish the site with the docs
tree missing. `publish-release.sh` runs the same script, so the hosted docs always match the
newest published build. The docs pages carry their own CSP rule in `firebase.json`. Asciidoctor
embeds its stylesheet inline, so `/docs/**` allows inline styles while everything else stays locked
to `'self'`.

## Copies of 1.1.0 and earlier no longer update

Copies of 1.1.0 and earlier ask `agreeable-glacier-0a845c510.7.azurestaticapps.net` for their feed,
because that hostname was compiled into them. It was the default hostname of the Azure Static Web
App that served the site until November 2026. Only that Azure app can answer on it, so those copies
get no updates since the site moved to Firebase. Sparkle treats an unreachable feed as
nothing to report, so they show no error. Their users must download the current release once.
Later builds ask `aerospork.app`, which follows the site wherever it is hosted.
