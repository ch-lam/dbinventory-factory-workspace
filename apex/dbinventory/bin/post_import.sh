#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The gate that runs AFTER `apex import`, and the reason it exists.
#
# `validate.sh` proves the .apx compiles. It never opens a page, and it cannot:
# page 71 passed five validations and still died at first render. This script
# checks what APEX actually holds once the application is in the database.
#
# The one it was written for is the fileUpload storage type. An item imported
# without `storage { type: appTempFiles }` lands on DB_COLUMN -- a BLOB column
# the item has no source for. Until 2026-11-10 the .apx was believed unable to say
# it -- the compiler metadata lists no such group -- and every import needed a
# manual step in the builder; the .apx now says it, and this gate proves the
# import kept it.
#
#   * On page 71 the item sits in a report region and the page dies loudly with
#     WWV_FLOW_NATIVE_ITEM.NO_VALID_BLOB_SOURCE.
#   * On page 85 it sits in a static content region, where the very same
#     metadata renders without complaint. The page looks right, the upload lands
#     nowhere, and the save process finds nothing in apex_application_temp_files.
#
# The silent one is the dangerous one, and no browser test catches it. That is
# why this is a script with an exit code and not a line in a README.
#
# Usage: ./post_import.sh <app_dir> [db_connection_name]
#   e.g. ./post_import.sh ../applications/dbinventory
#
# The smoke test belongs to the application: <app_dir>/tests/T_001_apex_page_smoke.sql.
#
# Same SQLcl prerequisites as validate.sh, for the same reasons -- JDK 17+, a
# dumb JLine terminal, and a stdin that is a real file. See _sqlcl_env.sh.
# ---------------------------------------------------------------------------
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_sqlcl_env.sh
source "$BIN_DIR/_sqlcl_env.sh"

APP_DIR="$(resolve_app_dir "${1:-}")" || exit 1
DB_CONN="${2:-DEMO_DBINVENTORY_dbinventory}"

SMOKE="$APP_DIR/tests/T_001_apex_page_smoke.sql"
if [[ ! -f "$SMOKE" ]]; then
   echo "ERROR: $SMOKE not found." >&2
   exit 1
fi

JDK="$(find_jdk)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/stdin"

echo "=== APEX page smoke test (live via $DB_CONN) ==="
JAVA_HOME="${JDK:-${JAVA_HOME:-}}" \
JAVA_TOOL_OPTIONS="$APEX_SQLCL_TOOL_OPTIONS" \
   sql -S -name "$DB_CONN" @"$SMOKE" < "$work/stdin" 2>&1 \
   | grep -v 'Picked up JAVA_TOOL_OPTIONS' | tee "$work/smoke.out"
rc="${PIPESTATUS[0]}"

echo
# Match T_001's own failure marker, at the start of the line and in capitals.
# A bare case-insensitive 'FAIL' also matched its summary line, "N checks run,
# 0 failure(s)", so this gate could never pass.
if [[ "$rc" -ne 0 ]] || grep -q '^  FAIL  ' "$work/smoke.out"; then
   cat >&2 <<'MSG'
ERROR: the imported application did not pass its smoke test.

If the failure names a fileUpload item, the item lacks its storage block. In
the .apx, give it

    storage {
        type: appTempFiles
    }

then validate and import again. The compiler accepts it (checked on 26.1.0+3102
and 26.2.0+3479) even though its metadata does not list it.
MSG
   exit 1
fi

echo "OK: the imported application holds what the .apx meant."
echo "    A clean run here is necessary, not sufficient: it inspects metadata and"
echo "    parses region SQL, it does not render a page. Open the pages that changed."
