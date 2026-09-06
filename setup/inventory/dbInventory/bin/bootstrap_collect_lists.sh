#!/bin/bash
# =============================================================================
# bootstrap_collect_lists  –  Amorce les tables *_collect_list depuis les .lst
#
# C'est l'exact inverse de gen_collect_lists.sh, et il ne sert qu'une fois par
# environnement. Le périmètre de collecte est censé vivre dans les tables
# *_collect_list ; gen_collect_lists.sh les rend en .lst avant chaque collecte.
# Mais aucune migration n'alimente ces tables : sur une base fraîchement
# installée elles sont vides, gen_collect_lists.sh génère 0 entrée active, son
# garde-fou refuse d'écraser les .lst et get_info_all.sh annule la collecte.
# Le périmètre réel n'existe donc que dans les fichiers. Ce script le remonte
# dans la base, une bonne fois, pour que la boucle se referme.
#
# Il n'écrit PAS dans la base : il produit du SQL sur la sortie standard. La
# cible est une décision humaine (quelle base porte le périmètre de production),
# et ce script n'a pas à la prendre ni à porter un mot de passe.
#
# Usage : bootstrap_collect_lists.sh [dossier_des_lst] > seed_collect_lists.sql
#         Défaut : ../collect (le dossier que lisent les scripts de collecte).
#         Puis :   sql -S -name <connexion> @seed_collect_lists.sql
#
# Conventions reprises de gen_collect_lists.sh, à l'identique :
#   - une ligne commentée (#) est une entrée connue et volontairement écartée :
#     elle est amorcée avec active = 0, pas omise ;
#   - mssql/postgres : ENV;LICENCE;hôte:port    oracle : ENV;LICENCE;ez_connect.
#
# Le SQL produit est un MERGE : rejouer le script ne duplique rien et ne perd
# pas les entrées ajoutées depuis l'application entre-temps.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${1:-${SCRIPT_DIR}/../collect}"

die() { echo "ERREUR: $*" >&2; exit 1; }

[[ -d "${SRC_DIR}" ]] || die "dossier introuvable : ${SRC_DIR}"

# Les .lst peuvent arriver en CRLF (édités sous Windows, ou sortis d'un checkout
# core.autocrlf) : le \r final se retrouverait sinon collé au port ou au service.
clean_lines() { sed 's/\r$//' "$1" | grep -v '^[[:space:]]*$'; }

# Une valeur de périmètre ne contient jamais d'apostrophe, mais on ne construit
# pas du SQL sans en doubler une : c'est le genre de garantie qui se démode.
q() { printf "'%s'" "${1//\'/\'\'}"; }

emit_header() {
    cat <<'SQL'
-- =============================================================================
-- Amorçage des tables *_collect_list depuis les fichiers .lst.
-- Généré par bin/bootstrap_collect_lists.sh — ne pas éditer à la main.
-- Rejouable : MERGE, pas INSERT.
-- =============================================================================
set define off
whenever sqlerror exit failure
SQL
}

# ── Oracle ────────────────────────────────────────────────────────────────────
# collect_name = le service de l'Easy Connect (host:port/SERVICE), qui est déjà
# la clé sur laquelle gen_collect_lists.sh trie le fichier.
emit_oracle() {
    local file="${SRC_DIR}/oracle_database_lists.lst" line active env lic tns name
    [[ -f "${file}" ]] || die "fichier introuvable : ${file}"
    echo
    echo "prompt -- oracle_collect_list"
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*# ]]; then
            active=0; line="${line#"${line%%[!#[:space:]]*}"}"; line="${line##\#}"
            while [[ "${line}" == \#* ]]; do line="${line##\#}"; done
        else
            active=1
        fi
        IFS=';' read -r env lic tns <<< "${line}"
        [[ -n "${tns:-}" ]] || die "ligne mal formée dans ${file} : ${line}"
        name="${tns##*/}"
        [[ -n "${name}" ]] || die "service absent de l'Easy Connect : ${line}"
        printf 'merge into oracle_collect_list t using (select %s collect_name, %s easy_connect_tns, %s environment, %s license_type, %s active from dual) s\n' \
            "$(q "${name}")" "$(q "${tns}")" "$(q "${env}")" "$(q "${lic}")" "${active}"
        printf '  on (t.collect_name = s.collect_name)\n'
        printf '  when matched then update set t.easy_connect_tns = s.easy_connect_tns, t.environment = s.environment, t.license_type = s.license_type, t.active = s.active\n'
        printf '  when not matched then insert (collect_name, easy_connect_tns, environment, license_type, active) values (s.collect_name, s.easy_connect_tns, s.environment, s.license_type, s.active);\n'
    done < <(clean_lines "${file}")
}

# ── MSSQL ─────────────────────────────────────────────────────────────────────
# Pas de collect_name : la clé est (hostname, port).
emit_mssql() {
    local file="${SRC_DIR}/mssql_database_lists.lst" line active env lic server host port
    [[ -f "${file}" ]] || die "fichier introuvable : ${file}"
    echo
    echo "prompt -- mssql_collect_list"
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*# ]]; then
            active=0; line="${line#"${line%%[!#[:space:]]*}"}"
            while [[ "${line}" == \#* ]]; do line="${line##\#}"; done
        else
            active=1
        fi
        IFS=';' read -r env lic server <<< "${line}"
        [[ -n "${server:-}" ]] || die "ligne mal formée dans ${file} : ${line}"
        server="${server%"${server##*[![:space:]]}"}"
        host="${server%%:*}"
        if [[ "${server}" == *:* ]]; then port="${server##*:}"; else port=1433; fi
        printf 'merge into mssql_collect_list t using (select %s hostname, %s port, %s environment, %s license_type, %s active from dual) s\n' \
            "$(q "${host}")" "${port}" "$(q "${env}")" "$(q "${lic}")" "${active}"
        printf '  on (t.hostname = s.hostname and t.port = s.port)\n'
        printf '  when matched then update set t.environment = s.environment, t.license_type = s.license_type, t.active = s.active\n'
        printf '  when not matched then insert (hostname, port, environment, license_type, active) values (s.hostname, s.port, s.environment, s.license_type, s.active);\n'
    done < <(clean_lines "${file}")
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────
# collect_name = premier label du FQDN, en majuscules : c'est ce qui distingue
# les instances entre elles, et la colonne ne fait que 30 caractères.
emit_postgres() {
    local file="${SRC_DIR}/postgres_database_lists.lst" line active env lic server host port name
    [[ -f "${file}" ]] || die "fichier introuvable : ${file}"
    echo
    echo "prompt -- postgres_collect_list"
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*# ]]; then
            active=0; line="${line#"${line%%[!#[:space:]]*}"}"
            while [[ "${line}" == \#* ]]; do line="${line##\#}"; done
        else
            active=1
        fi
        IFS=';' read -r env lic server <<< "${line}"
        [[ -n "${server:-}" ]] || die "ligne mal formée dans ${file} : ${line}"
        server="${server%"${server##*[![:space:]]}"}"
        host="${server%%:*}"
        if [[ "${server}" == *:* ]]; then port="${server##*:}"; else port=5432; fi
        name="${host%%.*}"
        name="$(printf '%s' "${name}" | tr '[:lower:]' '[:upper:]')"
        printf 'merge into postgres_collect_list t using (select %s collect_name, %s hostname, %s port, %s environment, %s license_type, %s active from dual) s\n' \
            "$(q "${name}")" "$(q "${host}")" "${port}" "$(q "${env}")" "$(q "${lic}")" "${active}"
        printf '  on (t.collect_name = s.collect_name)\n'
        printf '  when matched then update set t.hostname = s.hostname, t.port = s.port, t.environment = s.environment, t.license_type = s.license_type, t.active = s.active\n'
        printf '  when not matched then insert (collect_name, hostname, port, environment, license_type, active) values (s.collect_name, s.hostname, s.port, s.environment, s.license_type, s.active);\n'
    done < <(clean_lines "${file}")
}

emit_header
emit_oracle
emit_mssql
emit_postgres

echo
echo "commit;"
