#!/bin/sh
# Integration test of the session-list command against the DEV copy of the
# plugin (id "session-list-test"), driven from real scratch Tern panes.
# Usage: sh tests/cli.sh [scratch dir]   (default: a new mktemp dir)
#
# Never touches the real plugin: the real id is never linked, and the real
# data folder's listas/ is hashed before and after (ABSENT when missing).
# Never touches the person's windows: every pane lives in a dedicated session
# made here, and the "(shown)" markers of every window are compared at the end.
#
# How the windows stay unchanged (measured 2026-11-02, Tern 0.9.8):
# `tern new session NAME -- /bin/sh` adds a session WITHOUT changing which
# session or tab any window shows, and `tern new tab NAME -- /bin/sh` adds a
# tab to that session without changing them either. So no focus restore is
# needed; the end-of-test check proves it on every run.
set -u

P=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CMD=$P/bin/session-list
ID=session-list-test
SESSAO=sl-cli-test

if [ -n "${TERN_CONFIG_DIR:-}" ]; then
	TERN_DIR=$TERN_CONFIG_DIR
else
	TERN_DIR="$HOME/Library/Application Support/Tern"
fi
REAL="$TERN_DIR/plugin-data/session-list/listas"
DEV="$TERN_DIR/plugin-data/$ID"

case $DEV in
/*) ;;
*)
	echo "refusing: the dev data folder is not an absolute path: $DEV" >&2
	exit 1
	;;
esac
if [ "$(basename -- "$DEV")" != "$ID" ]; then
	echo "refusing: unexpected dev data folder: $DEV" >&2
	exit 1
fi

FEZ_SCRATCH=''
if [ $# -ge 1 ]; then
	SCRATCH=$1
	mkdir -p "$SCRATCH" || exit 1
else
	SCRATCH=$(mktemp -d) || exit 1
	FEZ_SCRATCH=1
fi
TMPF=$(mktemp) || exit 1
ERRF=$(mktemp) || exit 1

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

passo() {
	echo "ok - $*"
}

if command -v shasum >/dev/null 2>&1; then
	SHA='shasum -a 256'
else
	SHA=sha256sum
fi

# Hash of the real listas/: file names + contents; ABSENT when the folder is missing.
hash_real() {
	if [ ! -d "$REAL" ]; then
		echo ABSENT
		return
	fi
	find "$REAL" -type f -print | LC_ALL=C sort | while IFS= read -r f; do
		printf '%s\n' "$f"
		$SHA <"$f"
	done | $SHA | cut -d' ' -f1
}

# The keys of every window (from `tern inspect`'s clients), "" written as "".
janelas() {
	tern inspect | awk '$2 == "window" { k = $3; gsub(/"/, "", k); print k }'
}

# Which session and tab each window shows.
marcadores() {
	janelas | while IFS= read -r k; do
		echo "window [$k]"
		tern ls --window "$k" | grep '(shown)'
	done
}

pane_existe() {
	tern ls | grep -q "^ *$1 "
}

# Remove the dev data folder file by file, then its folders (never rm -rf).
limpa_dev() {
	if [ -d "$DEV" ]; then
		find "$DEV" -type f -exec rm -f {} \;
		find "$DEV" -depth -type d -exec rmdir {} \;
	fi
}

PANES=''
FEZ_SESSAO=''
LINKOU=''
HASH_ANTES=''
MARC_ANTES=''

cleanup() {
	rc=$?
	trap - EXIT INT TERM
	for p in $PANES; do
		if pane_existe "$p"; then
			tern close "$p" >/dev/null 2>&1
		fi
	done
	if [ -n "$FEZ_SESSAO" ]; then
		tern kill session "$SESSAO" >/dev/null 2>&1
	fi
	if [ -n "$LINKOU" ]; then
		tern plugin unlink "$ID" >/dev/null 2>&1 || {
			echo "FAIL: could not unlink $ID" >&2
			rc=1
		}
	fi
	limpa_dev
	if [ -d "$DEV" ]; then
		echo "FAIL: the dev data folder is still there: $DEV" >&2
		rc=1
	fi
	if [ -n "$FEZ_SCRATCH" ] && [ -d "$SCRATCH" ]; then
		find "$SCRATCH" -type f -exec rm -f {} \;
		find "$SCRATCH" -depth -type d -exec rmdir {} \;
	fi
	rm -f "$TMPF" "$ERRF"
	if [ -n "$HASH_ANTES" ]; then
		h=$(hash_real)
		if [ "$h" = "$HASH_ANTES" ]; then
			echo "ok - 8. cleanup: real listas/ hash unchanged ($h)"
		else
			echo "FAIL: the real listas/ changed: $HASH_ANTES -> $h" >&2
			rc=1
		fi
	fi
	if [ -n "$MARC_ANTES" ]; then
		if [ "$(marcadores)" = "$MARC_ANTES" ]; then
			echo "ok - 8. cleanup: every window shows what it showed at the start"
		else
			echo "FAIL: a window's shown session/tab changed" >&2
			echo "before:" >&2
			printf '%s\n' "$MARC_ANTES" >&2
			echo "after:" >&2
			marcadores >&2
			rc=1
		fi
	fi
	if pane_existe_sessao; then
		echo "FAIL: session $SESSAO is still there" >&2
		rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		echo "PASS"
	fi
	exit "$rc"
}

pane_existe_sessao() {
	[ -n "$FEZ_SESSAO" ] && tern ls | grep -q "^$SESSAO\( \|$\)"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# Runs the command as pane $1. Sets OUT, ERR, RC. Stdin: $SL_STDIN when set.
sl() {
	pane=$1
	shift
	if [ -n "${SL_STDIN+x}" ]; then
		printf '%s' "$SL_STDIN" >"$TMPF"
	else
		: >"$TMPF"
	fi
	OUT=$(env -u SESSION_LIST_NO_ORPHANS TERN_PANE="$pane" SESSION_LIST_DATA="$DEV" \
		sh "$CMD" "$@" <"$TMPF" 2>"$ERRF")
	RC=$?
	ERR=$(cat "$ERRF")
}

tem() { # haystack needle
	case $1 in
	*"$2"*) return 0 ;;
	esac
	return 1
}

espera_rc() { # expected rc, context
	[ "$RC" -eq "$1" ] || fail "$2: exit $RC, expected $1 (stdout: $OUT) (stderr: $ERR)"
}

nova_pane() { # session|tab -> prints the new pane id
	if [ "$1" = session ]; then
		j=$(tern new session "$SESSAO" --json -- /bin/sh) || return 1
	else
		j=$(tern new tab "$SESSAO" --json -- /bin/sh) || return 1
	fi
	printf '%s' "$j" | tr -d '\n ' | sed -n 's/.*"block":\([0-9][0-9]*\).*/\1/p'
}

# Waits up to 3 s for pane $1's `show` to list an orphan; prints its id.
espera_orfa() {
	inicio=$(date +%s)
	while :; do
		sl "$1" show
		if [ "$RC" -eq 0 ] && tem "$OUT" "Lists closed tabs left with open items:"; then
			printf '%s\n' "$OUT" | sed -n 's/^- \(l_[a-z0-9]\{8\}\).*/\1/p' | head -n 1
			return 0
		fi
		if [ $(($(date +%s) - inicio)) -gt 3 ]; then
			return 1
		fi
		sleep 0.1
	done
}

# ---- 1. the real data folder, before anything ---------------------------------
HASH_ANTES=$(hash_real)
passo "1. real listas/ hash before: $HASH_ANTES"

# ---- 2. scratch panes, without changing what the windows show -----------------
MARC_ANTES=$(marcadores)
[ -n "$MARC_ANTES" ] || fail "could not read the windows' shown markers"
if tern ls | grep -q "^$SESSAO\( \|$\)"; then
	MARC_ANTES=''
	fail "a session named $SESSAO already exists; not touching it"
fi
if tern plugin list | grep -q "$ID"; then
	tern plugin unlink "$ID" >/dev/null 2>&1 || fail "$ID was linked and could not be unlinked"
fi
limpa_dev

COPIA=$(sh "$P/tests/dev-copy.sh" "$SCRATCH" false) || fail "dev-copy.sh failed"
grep -q "^id = \"$ID\"\$" "$COPIA/plugin.toml" || fail "the copy's id is not $ID"
if grep -q '^id = "session-list"$' "$COPIA/plugin.toml"; then
	fail "the copy still carries the real id"
fi
LINKOU=1
tern plugin link "$COPIA" >/dev/null || fail "tern plugin link failed"
n=0
until tern plugin list | grep "$ID" | grep -q ready; do
	n=$((n + 1))
	[ "$n" -le 50 ] || fail "$ID did not load: $(tern plugin list)"
	sleep 0.1
done

FEZ_SESSAO=1
A=$(nova_pane session) && [ -n "$A" ] || fail "could not create the scratch session"
PANES="$A"
B=$(nova_pane tab) && [ -n "$B" ] || fail "could not create pane B"
PANES="$PANES $B"
[ "$(marcadores)" = "$MARC_ANTES" ] || fail "creating the scratch panes changed a window's shown session/tab"
passo "2. dev copy linked, scratch session $SESSAO with panes A=$A B=$B, windows unchanged"

# ---- 3. add, done, block, show, check ----------------------------------------
sl "$A" add "part one" "part two" "part three" --subject "cli test"
espera_rc 0 "add"
sl "$A" done i1
espera_rc 0 "done i1"
sl "$A" block i2 "waiting for X"
espera_rc 0 "block i2"
sl "$A" show
espera_rc 0 "show"
tem "$OUT" "This tab's session list: cli test" || fail "show: no subject header: $OUT"
tem "$OUT" "☐ i3 part three" || fail "show: no open line: $OUT"
tem "$OUT" "⊘ i2 part two (blocked: waiting for X)" || fail "show: no blocked line: $OUT"
tem "$OUT" "☑ i1 part one (done)" || fail "show: no done line: $OUT"
passo "3a. add 3, done i1, block i2, show has the ☑/⊘/☐ lines"

SL_STDIN='{}'
sl "$A" check --hook
espera_rc 2 "first check --hook"
tem "$ERR" "You stopped with 1 open item" || fail "check --hook: no reminder on stderr: $ERR"
tem "$ERR" "i3 part three" || fail "check --hook: reminder misses i3: $ERR"
[ -z "$OUT" ] || fail "check --hook: reminder went to stdout: $OUT"
sl "$A" check --hook
espera_rc 0 "second check --hook (cap 1)"
unset SL_STDIN
passo "3b. check --hook {} -> 2 with the reminder on stderr; again -> 0 (cap 1)"

sl "$A" undo i1
espera_rc 0 "undo i1"
SL_STDIN='{}'
sl "$A" check --hook
espera_rc 2 "check --hook after a change"
tem "$ERR" "2 open items" || fail "check after undo: expected 2 open items: $ERR"
unset SL_STDIN
passo "3c. undo i1 resets the cap: check --hook -> 2 again"

# a change before each, so a reminder WOULD be due if the input were ignored
sl "$A" name "cli test 2"
espera_rc 0 "name"
SL_STDIN='{"stop_hook_active":true}'
sl "$A" check --hook
espera_rc 0 "check --hook with stop_hook_active"
SL_STDIN='{"last_assistant_message":"Should I go on?"}'
sl "$A" check --hook
espera_rc 0 "check --hook after a question"
SL_STDIN='{}'
sl "$A" check --hook
espera_rc 2 "check --hook {} (control: a reminder was due)"
unset SL_STDIN
passo "3d. stop_hook_active -> 0, ending on a question -> 0 (control {} -> 2)"

# ---- 4. close A -> orphan seen from B -> adopt --------------------------------
tern close "$A" >/dev/null || fail "tern close $A"
ORFA_A=$(espera_orfa "$B") || fail "A's list did not show up as an orphan from B within 3 s: $OUT"
[ -n "$ORFA_A" ] || fail "no orphan id in B's show"
sl "$B" show # espera_orfa ran in a subshell: read the text here
tem "$OUT" "- $ORFA_A (cli test 2):" || fail "orphan line without its subject: $OUT"
tem "$OUT" "part two" || fail "orphan line misses the blocked item: $OUT"
passo "4a. closed A: B's show lists orphan $ORFA_A"

sl "$B" adopt "$ORFA_A"
espera_rc 0 "adopt from B"
tem "$OUT" "Moved list $ORFA_A to this tab." || fail "adopt: no notice: $OUT"
tem "$OUT" "⊘ i2 part two (blocked: waiting for X)" || fail "adopt: blocked reason lost: $OUT"
tem "$OUT" "☐ i1 part one" || fail "adopt: i1 missing: $OUT"
tem "$OUT" "☐ i3 part three" || fail "adopt: i3 missing: $OUT"
tem "$OUT" "Lists closed tabs left" && fail "adopt: the orphan is still offered: $OUT"
passo "4b. B adopted $ORFA_A: pending items kept, blocked reason kept"

# ---- 5. C with its own list adopts D's orphan: appended with new ids ---------
C=$(nova_pane tab) && [ -n "$C" ] || fail "could not create pane C"
PANES="$PANES $C"
D=$(nova_pane tab) && [ -n "$D" ] || fail "could not create pane D"
PANES="$PANES $D"
sl "$C" add "c item"
espera_rc 0 "add in C"
sl "$D" add "d one" "d two"
espera_rc 0 "add in D"
tern close "$D" >/dev/null || fail "tern close $D"
ORFA_D=$(espera_orfa "$C") || fail "D's list did not show up as an orphan from C within 3 s: $OUT"
[ -n "$ORFA_D" ] || fail "no orphan id in C's show: $OUT"
[ -f "$DEV/listas/$ORFA_D.json" ] || fail "orphan file missing before adopt: $DEV/listas/$ORFA_D.json"
sl "$C" adopt "$ORFA_D"
espera_rc 0 "adopt from C"
tem "$OUT" "☐ i1 c item" || fail "C's own item lost: $OUT"
tem "$OUT" "☐ i2 d one" || fail "d one not appended as i2: $OUT"
tem "$OUT" "☐ i3 d two" || fail "d two not appended as i3: $OUT"
[ ! -e "$DEV/listas/$ORFA_D.json" ] || fail "the adopted orphan's file is still there"
passo "5. C adopted $ORFA_D: appended as i2, i3; orphan file gone"

# ---- 6. discard an orphan -> descartadas/ -------------------------------------
E=$(nova_pane tab) && [ -n "$E" ] || fail "could not create pane E"
PANES="$PANES $E"
sl "$E" add "e one"
espera_rc 0 "add in E"
tern close "$E" >/dev/null || fail "tern close $E"
ORFA_E=$(espera_orfa "$C") || fail "E's list did not show up as an orphan from C within 3 s: $OUT"
[ -n "$ORFA_E" ] || fail "no orphan id for E: $OUT"
sl "$C" discard "$ORFA_E"
espera_rc 0 "discard"
tem "$OUT" "Discarded list $ORFA_E" || fail "discard: no notice: $OUT"
[ -f "$DEV/descartadas/$ORFA_E.json" ] || fail "discarded file not in descartadas/"
[ ! -e "$DEV/listas/$ORFA_E.json" ] || fail "discarded file still in listas/"
passo "6. discarded $ORFA_E: file moved to descartadas/"

# ---- 7. errors ----------------------------------------------------------------
sl "$C" frobnicate
espera_rc 1 "unknown verb"
tem "$ERR" "Unknown command" || fail "unknown verb: no message on stderr: $ERR"
sl "$C" done i99
espera_rc 0 "done of an unknown id"
tem "$OUT" "Not found: i99." || fail "done i99: no Not found notice: $OUT"
OUT=$(env -u TERN_PANE -u SESSION_LIST_NO_ORPHANS SESSION_LIST_DATA="$DEV" sh "$CMD" show </dev/null 2>"$ERRF")
RC=$?
ERR=$(cat "$ERRF")
espera_rc 1 "no TERN_PANE"
tem "$ERR" "only works inside a Tern pane" || fail "no TERN_PANE: wrong message: $ERR"
passo "7. errors: unknown verb -> 1, done i99 -> 0 + Not found, no TERN_PANE -> 1"

exit 0
