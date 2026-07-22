#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run both APEXLang validation gates against this app.
#
#   1. apex validate (SQLcl)        -> authoritative, live, needs a DB connection
#   2. compiler-truth audit (skill) -> offline diagnostic
#
# Usage: ./validate.sh [db_connection_name]
#
# Four non-obvious prerequisites are handled here; do not drop them:
#
#   * JAVA_HOME must point at a JDK 17+. SQLcl ships/defaults to a JRE 11 on
#     this machine, and oracle.apexlang.APEXLangCompiler is compiled for
#     class file version 61 -> UnsupportedClassVersionError otherwise.
#   * -Dorg.jline.terminal.provider=dumb. Under a captured (non-TTY) stdout
#     JLine cannot allocate a terminal on Windows: the ffm provider needs
#     --enable-native-access, and jansi/jna classes are absent.
#   * stdin must come from a real file. /dev/null and heredocs make SQLcl die
#     with "java.io.IOException: Fonction incorrecte" from System.in.available().
#   * .apx files must be LF. The APEXLang lexer rejects CR (see ../../../.gitattributes).
# ---------------------------------------------------------------------------
set -uo pipefail

DB_CONN="${1:-DEV_DBINVENTORY_dbinventory}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$APP_DIR/../../../.agents/skills/apex/apexlang" && pwd)"

# SQLcl is a Windows process: it reads /g/... as C:\g\..., so hand it a
# Windows-resolvable path. cygpath -m keeps forward slashes (no escaping).
APP_DIR_WIN="$APP_DIR"
if command -v cygpath >/dev/null 2>&1; then
   APP_DIR_WIN="$(cygpath -m "$APP_DIR")"
fi

JDK="${APEXLANG_JDK:-C:/Program Files/Java/jdk-24}"
if [[ ! -x "$JDK/bin/java.exe" && ! -x "$JDK/bin/java" ]]; then
   echo "ERROR: no JDK 17+ at '$JDK'. Set APEXLANG_JDK to one." >&2
   exit 1
fi

crlf=$(find "$APP_DIR" -name '*.apx' -exec file {} \; | grep -c CRLF || true)
if [[ "$crlf" -gt 0 ]]; then
   echo "ERROR: $crlf .apx file(s) have CRLF endings; apex validate will fail." >&2
   echo "Fix with: find '$APP_DIR' -name '*.apx' -exec sed -i 's/\r\$//' {} \\;" >&2
   exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'apex validate -input %s\nexit\n' "$APP_DIR_WIN" > "$work/av.sql"
: > "$work/stdin"

echo "=== apex validate (SQLcl, live via $DB_CONN) ==="
JAVA_HOME="$JDK" \
JAVA_TOOL_OPTIONS="-Duser.language=en -Xmx800m -Dorg.jline.terminal.provider=dumb" \
   sql -S -name "$DB_CONN" @"$work/av.sql" < "$work/stdin" 2>&1 \
   | grep -v 'Picked up JAVA_TOOL_OPTIONS' | tee "$work/live.out"

# SQLcl exits 0 even when apex validate reports errors or cannot read the
# input path, so key the exit status off the compiler's own verdict line.
if grep -q '^Validation successful\.' "$work/live.out"; then
   live_rc=0
else
   live_rc=1
   echo "ERROR: apex validate did not report success." >&2
fi

echo
echo "=== compiler-truth audit (offline) ==="
cd "$SKILL_DIR"
node tools/apexctl.mjs apexlang compiler-truth audit \
   --app-path "$APP_DIR" --verify-component-attributes 2>&1 | tail -20

echo
echo "Note: apex validate is the authoritative gate. The offline audit counts"
echo "parentheses line-by-line without skipping \`\`\`sql fences, so it reports"
echo "false positives on multi-line SQL; cross-check anything it flags."
exit "$live_rc"
