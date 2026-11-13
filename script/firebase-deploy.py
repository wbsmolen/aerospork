#!/usr/bin/env python3
"""Deploys the `hosting` section of firebase.json through the Firebase Hosting REST API.

Usage: script/firebase-deploy.py <dir-with-firebase.json> <project> [<site>]

It authenticates with `gcloud auth print-access-token`, so the only login it needs is gcloud's.
`npx firebase-tools deploy --only hosting` reads the same firebase.json and does the same job, with
a login of its own.
ponytail: handles headers, redirects, cleanUrls and trailingSlash, the keys this site uses. Add a
key here before you use it in firebase.json, or deploy with firebase-tools.
"""
import fnmatch, gzip, hashlib, json, os, subprocess, sys, urllib.request

root, project = sys.argv[1], sys.argv[2]
site = sys.argv[3] if len(sys.argv) > 3 else project
hosting = json.load(open(os.path.join(root, "firebase.json")))["hosting"]
public = os.path.join(root, hosting["public"])
token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
API = "https://firebasehosting.googleapis.com/v1beta1/"


def call(method, url, body=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url if url.startswith("http") else API + url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("x-goog-user-project", project)
    req.add_header("Content-Type", "application/octet-stream" if raw is not None else "application/json")
    with urllib.request.urlopen(req) as r:
        text = r.read()
        return json.loads(text) if text else {}


config = {}
if hosting.get("headers"):
    config["headers"] = [{"glob": h["source"], "headers": {x["key"]: x["value"] for x in h["headers"]}}
                         for h in hosting["headers"]]
if hosting.get("redirects"):
    config["redirects"] = [{"glob": r["source"], "location": r["destination"], "statusCode": r.get("type", 301)}
                           for r in hosting["redirects"]]
for k in ("cleanUrls", "trailingSlashBehavior"):
    if k in hosting:
        config[k] = hosting[k]
if "trailingSlash" in hosting:
    config["trailingSlashBehavior"] = "ADD" if hosting["trailingSlash"] else "REMOVE"

ignore = hosting.get("ignore", ["firebase.json", "**/.*", "**/node_modules/**"])


def ignored(rel):
    return any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(rel, g.removeprefix("**/")) for g in ignore)


files, blobs = {}, {}
for d, dirs, names in os.walk(public):
    for n in names:
        p = os.path.join(d, n)
        rel = os.path.relpath(p, public).replace(os.sep, "/")
        if ignored(rel):
            continue
        blob = gzip.compress(open(p, "rb").read(), mtime=0)
        h = hashlib.sha256(blob).hexdigest()
        files["/" + rel] = h
        blobs[h] = blob

version = call("POST", f"sites/{site}/versions", {"config": config})["name"]
pop = call("POST", f"{version}:populateFiles", {"files": files})
for h in pop.get("uploadRequiredHashes", []):
    call("POST", f"{pop['uploadUrl']}/{h}", raw=blobs[h])
call("PATCH", f"{version}?update_mask=status", {"status": "FINALIZED"})
call("POST", f"sites/{site}/releases?versionName={version}", {})
print(f"released {len(files)} files to https://{site}.web.app ({version})")
