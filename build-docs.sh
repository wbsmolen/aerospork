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
        bundler exec asciidoctor ./guide.adoc ./commands.adoc ./goodies.adoc
        rm -rf ./*.adoc
    cd - > /dev/null

    git rev-parse HEAD > .site/version.html
    if ! test -z "$(git status --porcelain)"; then
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
