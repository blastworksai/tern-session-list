#!/bin/sh
# Makes the DEV copy of the plugin (id "session-list-test") so tests never
# touch the real plugin's id or data.
# Usage: sh dev-copy.sh <scratch dir> [abrir_sozinho true|false]   (default false)
# Prints the copy's path. The copy's kv.json is written before linking.
set -eu

if [ $# -lt 1 ]; then
	echo "usage: sh dev-copy.sh <scratch dir> [true|false]" >&2
	exit 1
fi
SCRATCH=$1
ABRIR=${2:-false}
case $ABRIR in
true | false) ;;
*)
	echo "abrir_sozinho must be true or false, got: $ABRIR" >&2
	exit 1
	;;
esac

ID=session-list-test
P=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ -n "${TERN_CONFIG_DIR:-}" ]; then
	TERN_DIR=$TERN_CONFIG_DIR
else
	TERN_DIR="$HOME/Library/Application Support/Tern"
fi
DATA="$TERN_DIR/plugin-data/$ID"

# Guard: never the real plugin's data folder.
if [ "$(basename -- "$DATA")" = "session-list" ]; then
	echo "refusing: the target data folder is the real plugin's ($DATA)" >&2
	exit 1
fi

COPY="$SCRATCH/$ID"
mkdir -p "$COPY"
# copy the plugin (not the tests' scratch output), then rewrite id and name
cp -R "$P/." "$COPY/"
sed -e 's/^id = "session-list"$/id = "session-list-test"/' \
	-e 's/^name = "Session list"$/name = "Session list (test)"/' \
	"$P/plugin.toml" >"$COPY/plugin.toml"

if ! grep -q '^id = "session-list-test"$' "$COPY/plugin.toml"; then
	echo "refusing: could not rewrite the id in $COPY/plugin.toml" >&2
	exit 1
fi

mkdir -p "$DATA"
printf '{"abrir_sozinho": %s, "idioma": "en", "max_lembretes": 1}\n' "$ABRIR" >"$DATA/kv.json"

echo "$COPY"
