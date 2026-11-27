#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --bundler

rm -rf .site && mkdir .site
rm -rf .man && mkdir .man

cp-docs() {
    cp -r ./docs/*.adoc "$1"
    cp -r ./docs/assets "$1"
    cp -r ./docs/util "$1"
    cp -r ./docs/config-examples "$1"
}

build-site() {
    cp-docs ./.site
    cp ./docs/index.html ./.site

    cd .site
        # Delete "aerospork " prefifx in synopsis
        sed -E -i '' '/tag::synopsis/, /end::synopsis/ s/^(aerospork | {10})//' aerospork*
        # webfonts! drops the Google Fonts <link>: aerospork.app serves these pages under a CSP
        # with no third-party origins, and the site promises no third-party requests at all.
        # Asciidoctor's stylesheet falls back to system font stacks.
        bundler exec asciidoctor -a webfonts! ./guide.adoc ./commands.adoc ./goodies.adoc
        rm -rf ./*.adoc
    cd - > /dev/null

    git rev-parse HEAD > .site/version.html
    # Not appcast.xml: a release modifies it just before deploy-site.sh builds these docs.
    if ! test -z "$(git status --porcelain -- . ':!updates-site/appcast.xml')"; then
        echo "git working directory is dirty" >> .site/version.html
    fi
}

build-man() {
    cp-docs .man
    cd .man
        bundler exec asciidoctor -b manpage aerospork*.adoc
        rm -rf -- *.adoc
    cd - > /dev/null
}

build-site
build-man
