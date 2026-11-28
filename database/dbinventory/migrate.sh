#!/usr/bin/env bash
# Applies the migrations of schema DBINVENTORY through a saved SQLcl connection.
#
#   database/dbinventory/migrate.sh <connection>             apply what is pending
#   database/dbinventory/migrate.sh <connection> --dry-run   only say what is pending
#
# 1. V__NNN_<what>.sql: versioned migrations (tables, data). Each is applied
#    once, in name order, and recorded with its SHA-256 in the table
#    DBINVENTORY.SCHEMA_MIGRATIONS. A recorded file whose content changed is
#    refused: never edit an applied migration, add the next V__ file instead.
#    The checksum ignores carriage returns, so a Windows (CRLF) checkout and a
#    Linux (LF) checkout of the same file agree.
# 2. R__<object>.sql: rerunnable code (create or replace), replayed on every run
#    in the order listed in R__order.txt (package specs, views, bodies, then
#    triggers). Every R__ file must be listed there. The schema is recompiled
#    after the replay.
# 3. T__*.sql: checks, run last. T__000 fails on any invalid object, T__001 on
#    any use of a licensed Oracle option.
#
# X_000_reinstall_all.sql installs the same files in one SQLcl run, for a
# temporary environment. Both modes check first that it lists exactly the V__,
# the R__ of R__order.txt and the T__, in that order, so the two installs
# cannot drift apart.
#
# Nothing is ever dropped. The run stops at the first error. Applying needs the
# schema owner's connection; --dry-run also works with a read-only one.
#
# PORTABLE ON PURPOSE -- Linux (factory host) AND Git Bash on Windows (the
# owner's workstation: temporary environments, tests). Keep the stdin from a
# real file, -Dorg.jline.terminal.provider=dumb and the cygpath conversion:
# without them SQLcl on Windows answers "java.io.IOException" in place of the
# result and exits 0, so a run that did nothing reports success. Changing this
# needs the owner's written approval: see AGENTS.md, "Outillage portable".
#
# Seeded by the Factory Seed; this repository owns it from then on.
set -Eeuo pipefail

die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
log() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONN="${1:-}"
DRY_RUN=false
[[ "${2:-}" == --dry-run ]] && DRY_RUN=true
[[ -n "$CONN" && "$CONN" != -* ]] || die "usage: $0 <sqlcl-connection-name> [--dry-run]"
[[ $# -le 2 && ( $# -lt 2 || "${2:-}" == --dry-run ) ]] || die "usage: $0 <sqlcl-connection-name> [--dry-run]"
command -v sql >/dev/null 2>&1 || die "SQLcl (sql) is not on the PATH."
SCHEMA="$(basename "$DIR" | tr '[:lower:]' '[:upper:]')"
[[ "$SCHEMA" =~ ^[A-Z][A-Z0-9_]{0,29}$ ]] || die "The folder name $(basename "$DIR") is not a schema name."
cd "$DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/stdin"

# SQLcl on Windows reads /g/... as C:\g\...: hand it a path it can resolve.
# Without cygpath (Linux) the path is already right.
to_win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# The checksum of a migration, carriage returns left out.
checksum() { tr -d '\r' < "$1" | sha256sum | cut -c1-64; }

# Runs the SQLcl script read on stdin through the connection. The script is
# written to a file and SQLcl reads its own stdin from an empty real file (see
# the header). SQLcl exits 0 after many errors on its own, so the script stops
# at the first SQL or OS error, and SP2- messages and Java I/O errors count as
# failures too.
run_sql() {
  local out rc=0
  { printf 'whenever sqlerror exit failure rollback\nwhenever oserror exit failure rollback\nset define off\n'
    cat
    printf '\nexit\n'; } > "$WORK/script.sql"
  JAVA_TOOL_OPTIONS="-Duser.language=en -Dorg.jline.terminal.provider=dumb${JAVA_TOOL_OPTIONS:+ $JAVA_TOOL_OPTIONS}" \
    sql -S -name "$CONN" @"$(to_win "$WORK/script.sql")" < "$WORK/stdin" > "$WORK/out" 2>&1 || rc=$?
  out="$(grep -v 'Picked up JAVA_TOOL_OPTIONS' "$WORK/out" || true)"
  printf '%s\n' "$out"
  (( rc == 0 )) && ! grep -Eq '^(SP2-[0-9]+|Error starting at line)|java\.io\.IOException' <<<"$out"
}

# '@"<absolute path>"' lines for SQLcl, from file names of this folder.
at_lines() { local f; for f in "$@"; do printf '@"%s"\n' "$(to_win "$DIR/$f")"; done; }

# --- Files -------------------------------------------------------------------
mapfile -t V_FILES < <(find . -maxdepth 1 -type f -name 'V__*.sql' -printf '%f\n' | LC_ALL=C sort)
for f in "${V_FILES[@]}"; do
  [[ "$f" =~ ^V__[0-9]{3,}_[A-Za-z0-9_]+\.sql$ ]] || die "Migration name not allowed: '$f' (expected V__NNN_<words>.sql)."
done
R_ORDER=()
if [[ -f R__order.txt ]]; then
  mapfile -t R_ORDER < <(sed -e 's/\r$//' -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' R__order.txt)
fi
for f in "${R_ORDER[@]}"; do
  [[ "$f" =~ ^R__[A-Za-z0-9_]+\.sql$ ]] || die "R__order.txt names '$f', which is not an R__<object>.sql file."
  [[ -f "$f" ]] || die "R__order.txt names $f, which does not exist."
done
while IFS= read -r f; do
  printf '%s\n' "${R_ORDER[@]}" | grep -qxF "$f" || die "$f is not listed in R__order.txt: add it where its dependencies come first."
done < <(find . -maxdepth 1 -type f -name 'R__*.sql' -printf '%f\n' | LC_ALL=C sort)
mapfile -t T_FILES < <(find . -maxdepth 1 -type f -name 'T__*.sql' -printf '%f\n' | LC_ALL=C sort)

# --- X_000 lists the same install ----------------------------------------------
if [[ -f X_000_reinstall_all.sql ]]; then
  expected="$(printf '%s\n' "${V_FILES[@]}" "${R_ORDER[@]}" "${T_FILES[@]}")"
  listed="$(sed -n -e 's/\r$//' -e 's/^@"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' X_000_reinstall_all.sql)"
  if [[ "$listed" != "$expected" ]]; then
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$listed") | sed 's/^/        /' >&2 || true
    die "X_000_reinstall_all.sql does not list the V__, R__ (R__order.txt order) and T__ files of migrate.sh ('<' expected, '>' listed). Update it."
  fi
else
  die "X_000_reinstall_all.sql is missing: it is the install for a temporary environment, keep it."
fi

# --- Ledger -----------------------------------------------------------------
# Read first, through any connection that can see the schema; created below,
# only by the schema owner.
LEDGER="$(run_sql <<SQL
set serveroutput on size unlimited
set feedback off
declare
  n pls_integer;
  c sys_refcursor;
  line varchar2(400);
begin
  dbms_output.put_line('USER|' || user);
  select count(*) into n from all_tables where owner = '$SCHEMA' and table_name = 'SCHEMA_MIGRATIONS';
  if n = 1 then
    open c for 'select file_name || ''|'' || checksum from $SCHEMA.schema_migrations order by file_name';
    loop
      fetch c into line;
      exit when c%notfound;
      dbms_output.put_line('DONE|' || line);
    end loop;
    close c;
  end if;
end;
/
SQL
)" || { printf '%s\n' "$LEDGER" >&2; die "Could not read the migration ledger through $CONN."; }

CONNECTED_AS="$(sed -n 's/\r$//; s/^USER|//p' <<<"$LEDGER" | head -1)"
[[ -n "$CONNECTED_AS" ]] || { printf '%s\n' "$LEDGER" >&2; die "Could not read the connected user through $CONN."; }
if ! $DRY_RUN && [[ "$CONNECTED_AS" != "$SCHEMA" ]]; then
  die "$CONN connects as $CONNECTED_AS; migrations of $SCHEMA apply as $SCHEMA. Use --dry-run to only read."
fi
if ! $DRY_RUN; then
  run_sql >/dev/null <<'SQL' || die "Could not create the ledger SCHEMA_MIGRATIONS through $CONN."
declare
  already_exists exception;
  pragma exception_init(already_exists, -955);
begin
  execute immediate 'create table schema_migrations (
     file_name  varchar2(200) primary key,
     checksum   varchar2(64)  not null,
     applied_at timestamp     default systimestamp not null,
     applied_by varchar2(128) default user not null)';
exception
  when already_exists then null;
end;
/
SQL
fi
declare -A APPLIED=()
while IFS='|' read -r tag file sum; do
  sum="${sum%$'\r'}"
  [[ "$tag" == DONE ]] && APPLIED["$file"]="$sum"
done <<<"$LEDGER"

# --- Versioned migrations ----------------------------------------------------
PENDING=()
for f in "${V_FILES[@]}"; do
  sum="$(checksum "$f")"
  if [[ -n "${APPLIED[$f]+x}" ]]; then
    [[ "${APPLIED[$f]}" == "$sum" ]] \
      || die "$f was applied with another content. Never edit an applied migration: restore it and add a new V__ file."
  else
    PENDING+=("$f")
  fi
done
for f in "${!APPLIED[@]}"; do
  [[ -f "$f" ]] || printf '[WARN] %s is recorded as applied but no longer in this folder.\n' "$f" >&2
done

# The same summary in both modes, so a log always shows what was found.
log "Schema $SCHEMA through $CONN (connected as $CONNECTED_AS): ${#APPLIED[@]} migration(s) recorded, ${#V_FILES[@]} V__ file(s) in $(basename "$DIR")/"
ok "X_000_reinstall_all.sql lists the same install"
if $DRY_RUN; then
  if (( ${#PENDING[@]} )); then
    log "Pending: ${PENDING[*]}"
  else
    ok "No pending migration"
  fi
  log "On apply, also replayed: ${#R_ORDER[@]} R__ file(s), then ${#T_FILES[@]} check(s)"
  exit 0
fi

for f in "${PENDING[@]}"; do
  sum="$(checksum "$f")"
  log "Applying $f"
  { at_lines "$f"; printf "insert into schema_migrations (file_name, checksum) values ('%s', '%s');\ncommit;\n" "$f" "$sum"; } \
    | run_sql || die "$f failed: nothing was recorded. A DDL already run stays; fix it before rerunning."
  ok "Applied $f"
done
(( ${#PENDING[@]} )) || ok "No pending migration"

if (( ${#R_ORDER[@]} )); then
  log "Replaying ${#R_ORDER[@]} R__ file(s)"
  at_lines "${R_ORDER[@]}" | run_sql || die "Replaying the R__ files failed."
  ok "R__ files replayed"
fi

# A view or trigger replayed before what it references stays INVALID until its
# first use: recompile, so that T__000 only reports what really does not compile.
run_sql >/dev/null <<'SQL' || die "Recompiling the schema failed."
begin
  dbms_utility.compile_schema(schema => user, compile_all => false);
end;
/
SQL

for f in "${T_FILES[@]}"; do
  log "Checking $f"
  at_lines "$f" | run_sql || die "$f failed: the schema is not in a valid state."
done
ok "Schema $SCHEMA is migrated and valid"
