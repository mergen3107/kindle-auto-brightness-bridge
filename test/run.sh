#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: %s /path/to/koreader-master\n' "$0" >&2
    exit 2
fi

KOREADER_ROOT=$1
PLUGIN_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUSTED=${BUSTED:-busted}

if [ ! -f "$KOREADER_ROOT/frontend/device/devicelistener.lua" ]; then
    printf 'KOReader source tree not found: %s\n' "$KOREADER_ROOT" >&2
    exit 2
fi

export KINDLE_AUTO_BRIGHTNESS_ROOT=$PLUGIN_ROOT
export KINDLE_AUTO_BRIGHTNESS_KO=$KOREADER_ROOT

exec "$BUSTED" --verbose \
    "$PLUGIN_ROOT/spec/unit/kindleautobrightness_spec.lua"
