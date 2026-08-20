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

# Find a JDK, in order of decreasing certainty. Do NOT hardcode a version here:
# this script used to pin C:/Program Files/Java/jdk-24, the machine was upgraded
# to 26, and it began failing with "no JDK" on a box that had one.
usable_jdk() { [[ -x "$1/bin/java.exe" || -x "$1/bin/java" ]]; }

JDK=""
for candidate in "${APEXLANG_JDK:-}" "${JAVA_HOME:-}"; do
   [[ -n "$candidate" ]] && usable_jdk "$candidate" && { JDK="$candidate"; break; }
done
if [[ -z "$JDK" ]]; then
   # Highest-numbered JDK under the usual install roots. Version sort, so
   # jdk-9 does not beat jdk-24.
   while IFS= read -r candidate; do
      usable_jdk "$candidate" && { JDK="$candidate"; break; }
   done < <(ls -d "/c/Program Files/Java"/jdk-* "/usr/lib/jvm"/*jdk* 2>/dev/null | sort -V -r)
fi
if [[ -z "$JDK" ]]; then
   echo "ERROR: no JDK 17+ found. Set APEXLANG_JDK to one." >&2
   echo "  The APEXlang compiler needs 17+; SQLcl may ship an older JRE, which" >&2
   echo "  surfaces as UnsupportedClassVersionError rather than as a version." >&2
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
echo "Note: apex validate is the authoritative gate. The offline audit now skips"
echo "\`\`\`sql/\`\`\`plsql fences, so multi-line SQL no longer produces phantom"
echo "properties; treat anything it flags as real and cross-check it."
exit "$live_rc"
