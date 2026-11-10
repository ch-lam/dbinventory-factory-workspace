#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run both APEXLang validation gates against one application of the workspace.
#
#   1. apex validate (SQLcl)        -> authoritative, live, needs a DB connection
#   2. compiler-truth audit (skill) -> offline diagnostic
#
# Usage: ./validate.sh <app_dir> [db_connection_name]
#   e.g. ./validate.sh ../applications/dbinventory
#
# The SQLcl prerequisites (JDK 17+, dumb JLine terminal, stdin from a real
# file) are explained in _sqlcl_env.sh; do not drop them. One more is checked
# here: .apx files must be LF. The APEXLang lexer rejects CR (see the
# .gitattributes at the repository root).
# ---------------------------------------------------------------------------
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_sqlcl_env.sh
source "$BIN_DIR/_sqlcl_env.sh"

APP_DIR="$(resolve_app_dir "${1:-}")" || exit 1
DB_CONN="${2:-DEV_DBINVENTORY_dbinventory}"
SKILL_DIR="$(cd "$BIN_DIR/../../../.agents/skills/apex/apexlang" && pwd)"
APP_DIR_WIN="$(to_win "$APP_DIR")"

JDK="$(find_jdk)"
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

echo "=== apex validate (SQLcl, live via $DB_CONN) on $(basename "$APP_DIR") ==="
JAVA_HOME="$JDK" \
JAVA_TOOL_OPTIONS="$APEX_SQLCL_TOOL_OPTIONS" \
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
# Same compiler as apex validate above; see sqlcl_compiler_jar for why.
COMPILER_JAR="$(sqlcl_compiler_jar)"
compiler_opt=()
if [[ -n "$COMPILER_JAR" ]]; then
   echo "compiler: $COMPILER_JAR"
   compiler_opt=( --compiler-oracle-home "$(to_win "$COMPILER_JAR")" )
else
   echo "WARNING: no APEXLang compiler found next to SQLcl; the audit picks its own," >&2
   echo "         which may not be the one apex validate used." >&2
fi
cd "$SKILL_DIR"
node tools/apexctl.mjs apexlang compiler-truth audit \
   --app-path "$APP_DIR" --verify-component-attributes "${compiler_opt[@]}" 2>&1 | tail -20

echo
echo "Note: apex validate is the authoritative gate. The offline audit now skips"
echo "\`\`\`sql/\`\`\`plsql fences, so multi-line SQL no longer produces phantom"
echo "properties; treat anything it flags as real and cross-check it."
exit "$live_rc"
