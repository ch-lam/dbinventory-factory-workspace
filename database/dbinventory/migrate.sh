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
# 2. R__<object>.sql: rerunnable code (create or replace), replayed on every run
#    in the order listed in R__order.txt (views, standalone units, package
#    specs, then bodies). Every R__ file must be listed there.
# 3. T__*.sql: checks, run last. T__000 fails on any invalid object.
#
# Nothing is ever dropped. The run stops at the first error. Applying needs the
# schema owner's connection; --dry-run also works with a read-only one.
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

# Runs the SQLcl script read on stdin through the connection. SQLcl exits 0
# after many errors on its own, so the script stops at the first SQL or OS
# error, and SP2- messages count as failures too.
run_sql() {
  local out rc=0
  out="$( { printf 'whenever sqlerror exit failure rollback\nwhenever oserror exit failure rollback\nset define off\n'
            cat
            printf '\nexit\n'; } | sql -S -name "$CONN" 2>&1 )" || rc=$?
  printf '%s\n' "$out"
  (( rc == 0 )) && ! grep -Eq '^(SP2-[0-9]+|Error starting at line)' <<<"$out"
}

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

CONNECTED_AS="$(sed -n 's/^USER|//p' <<<"$LEDGER" | head -1)"
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
  [[ "$tag" == DONE ]] && APPLIED["$file"]="$sum"
done <<<"$LEDGER"

# --- Versioned migrations ----------------------------------------------------
mapfile -t V_FILES < <(find . -maxdepth 1 -type f -name 'V__*.sql' -printf '%f\n' | LC_ALL=C sort)
PENDING=()
for f in "${V_FILES[@]}"; do
  [[ "$f" =~ ^V__[0-9]{3,}_[A-Za-z0-9_]+\.sql$ ]] || die "Migration name not allowed: '$f' (expected V__NNN_<words>.sql)."
  sum="$(sha256sum "$f" | cut -c1-64)"
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

# --- Rerunnable code and checks ---------------------------------------------
R_ORDER=()
if [[ -f R__order.txt ]]; then
  mapfile -t R_ORDER < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' R__order.txt)
fi
for f in "${R_ORDER[@]}"; do
  [[ "$f" =~ ^R__[A-Za-z0-9_]+\.sql$ ]] || die "R__order.txt names '$f', which is not an R__<object>.sql file."
  [[ -f "$f" ]] || die "R__order.txt names $f, which does not exist."
done
while IFS= read -r f; do
  printf '%s\n' "${R_ORDER[@]}" | grep -qxF "$f" || die "$f is not listed in R__order.txt: add it where its dependencies come first."
done < <(find . -maxdepth 1 -type f -name 'R__*.sql' -printf '%f\n' | LC_ALL=C sort)
mapfile -t T_FILES < <(find . -maxdepth 1 -type f -name 'T__*.sql' -printf '%f\n' | LC_ALL=C sort)

# The same summary in both modes, so a log always shows what was found.
log "Schema $SCHEMA through $CONN (connected as $CONNECTED_AS): ${#APPLIED[@]} migration(s) recorded, ${#V_FILES[@]} V__ file(s) in $(basename "$DIR")/"
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
  sum="$(sha256sum "$f" | cut -c1-64)"
  log "Applying $f"
  run_sql <<SQL || die "$f failed: nothing was recorded. A DDL already run stays; fix it before rerunning."
@"$f"
insert into schema_migrations (file_name, checksum) values ('$f', '$sum');
commit;
SQL
  ok "Applied $f"
done
(( ${#PENDING[@]} )) || ok "No pending migration"

if (( ${#R_ORDER[@]} )); then
  log "Replaying ${#R_ORDER[@]} R__ file(s)"
  printf '@"%s"\n' "${R_ORDER[@]}" | run_sql || die "Replaying the R__ files failed."
  ok "R__ files replayed"
fi

for f in "${T_FILES[@]}"; do
  log "Checking $f"
  printf '@"%s"\n' "$f" | run_sql || die "$f failed: the schema is not in a valid state."
done
ok "Schema $SCHEMA is migrated and valid"
