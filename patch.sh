#!/usr/bin/env bash
set -euo pipefail

err() {
    >&2 echo "$@"
}

usage() {
    err "usage: $1 ThePathOfYourOpenRestySrcDirectory"
    exit 1
}

failed_to_cd() {
    err "failed to cd $1"
    exit 1
}

if [[ $# != 1 ]]; then
    usage "$0"
fi

if [[ "$1" == *openresty-1.19.3.* ]]; then
    patch="$PWD/nginx-1.19.3.patch"
    dir="$1/bundle/nginx-1.19.3"
elif [[ "$1" == *openresty-1.19.9.* ]]; then
    patch="$PWD/nginx-1.19.9.patch"
    dir="$1/bundle/nginx-1.19.9"
elif [[ "$1" == *openresty-1.21.4.* ]]; then
    patch="$PWD/nginx-1.21.4.patch"
    dir="$1/bundle/nginx-1.21.4"
elif [[ "$1" == *openresty-1.25.3.* ]]; then
    patch="$PWD/nginx-1.25.3.patch"
    dir="$1/bundle/nginx-1.25.3"
elif [[ "$1" == *openresty-1.27.1.* ]]; then
    patch="$PWD/nginx-1.27.1.patch"
    dir="$1/bundle/nginx-1.27.1"
else
    err "can't detect OpenResty version"
    exit 1
fi

cd "$dir" || failed_to_cd "$dir"
echo "Start to patch $patch to $dir..."
patch -p0 --verbose < "$patch"
