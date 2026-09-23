#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The gate that runs AFTER `apex import`, and the reason it exists.
#
# `validate.sh` proves the .apx compiles. It never opens a page, and it cannot:
# page 71 passed five validations and still died at first render. This script
# checks what APEX actually holds once the application is in the database.
#
# The one it was written for is the fileUpload storage type. APEXlang has no
# property group for plugin attributes on a page item, so `Storage Type` cannot
# be expressed in the .apx and EVERY import resets it to DB_COLUMN -- a BLOB
# column the item has no source for.
#
#   * On page 71 the item sits in a report region and the page dies loudly with
#     WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE.
#   * On page 85 it sits in a static content region, where the very same
#     metadata renders without complaint. The page looks right, the upload lands
#     nowhere, and the save process finds nothing in apex_application_temp_files.
#
# The silent one is the dangerous one, and no browser test catches it. That is
# why this is a script with an exit code and not a line in a README: the manual
# step remains manual, but forgetting it now stops the deployment instead of
# shipping a form that quietly loses files.
#
# Usage: ./post_import.sh [db_connection_name]
#
# Same three SQLcl prerequisites as validate.sh, for the same reasons -- JDK
# 17+, a dumb JLine terminal, and a stdin that is a real file. Do not drop them.
# ---------------------------------------------------------------------------
set -uo pipefail

DB_CONN="${1:-DEV_DBINVENTORY_dbinventory}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$(cd "$APP_DIR/.." && pwd)"

SMOKE="$SQL_DIR/T_001_apex_page_smoke.sql"
if [[ ! -f "$SMOKE" ]]; then
   echo "ERROR: $SMOKE not found." >&2
   exit 1
fi

# SQLcl is a Windows process: it reads /g/... as C:\g\....
to_win() {
   if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

usable_jdk() { [[ -x "$1/bin/java.exe" || -x "$1/bin/java" ]]; }

JDK=""
for candidate in "${APEXLANG_JDK:-}" "${JAVA_HOME:-}"; do
   [[ -n "$candidate" ]] && usable_jdk "$candidate" && { JDK="$candidate"; break; }
done
if [[ -z "$JDK" ]]; then
   while IFS= read -r candidate; do
      usable_jdk "$candidate" && { JDK="$candidate"; break; }
   done < <(ls -d "/c/Program Files/Java"/jdk-* "/usr/lib/jvm"/*jdk* 2>/dev/null | sort -V -r)
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/stdin"

echo "=== APEX page smoke test (live via $DB_CONN) ==="
JAVA_HOME="${JDK:-${JAVA_HOME:-}}" \
JAVA_TOOL_OPTIONS="-Duser.language=en -Dorg.jline.terminal.provider=dumb" \
   sql -S -name "$DB_CONN" @"$(to_win "$SMOKE")" < "$work/stdin" 2>&1 \
   | grep -v 'Picked up JAVA_TOOL_OPTIONS' | tee "$work/smoke.out"
rc="${PIPESTATUS[0]}"

echo
if [[ "$rc" -ne 0 ]] || grep -qi 'FAIL' "$work/smoke.out"; then
   cat >&2 <<'MSG'
ERROR: the imported application did not pass its smoke test.

If the failure names a fileUpload item, it is the known manual step. In the
APEX builder, for EACH item listed above:

    Page 71 -> P71_UPLOAD        Settings > Storage Type
    Page 85 -> P85_UPLOAD        Settings > Storage Type

  set it to "Table APEX_APPLICATION_TEMP_FILES", save, then run this script
  again. It is not expressible in the .apx and every import resets it; see
  APEXLang/DEPLOY.md.
MSG
   exit 1
fi

echo "OK: the imported application holds what the .apx meant."
echo "    A clean run here is necessary, not sufficient: it inspects metadata and"
echo "    parses region SQL, it does not render a page. Open the pages that changed."
