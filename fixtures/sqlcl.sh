# =============================================================================
# sqlcl.sh  –  Appel de SQLcl utilisable depuis Git Bash sous Windows
#
# À sourcer, pas à exécuter.
#
# Deux prérequis non évidents, les mêmes que dans apex/dbinventory/bin/_sqlcl_env.sh, et pour
# les mêmes raisons. Ne pas les retirer :
#
#   * stdin doit venir d'un VRAI fichier. Sans TTY, /dev/null et un stdin
#     hérité fermé font mourir SQLcl sur « java.io.IOException: Fonction
#     incorrecte », levée par System.in.available() sur un handle Windows
#     invalide. Le symptôme est traître : SQLcl écrit le message sur sa sortie
#     standard, à la place du résultat de la requête, et rend 0.
#   * -Dorg.jline.terminal.provider=dumb. Sortie capturée donc non-TTY, et
#     JLine n'alloue pas de terminal sous Windows : le fournisseur ffm réclame
#     --enable-native-access, jansi et jna sont absents. Le « .dumb=true » seul
#     ne suffit pas, c'est bien « .provider » qu'il faut.
#
# Sur le serveur de production (Linux, avec TTY) ces deux réglages sont sans
# effet : ils ne changent donc rien à la chaîne réelle, ils la rendent
# seulement jouable depuis un poste de développement.
# =============================================================================

# SQLcl est un binaire Windows : il lit /g/... comme C:\g\.... On lui passe un
# chemin qu'il sait résoudre. cygpath -m garde les slashes (rien à échapper).
sqlcl_to_win() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# sqlcl_run <connexion> <script.sql> [arguments du script...]
# Rend la sortie de SQLcl débarrassée du bavardage de la JVM.
sqlcl_run() {
    local conn="$1" script="$2"; shift 2
    local args=() a
    for a in "$@"; do args+=( "$(sqlcl_to_win "${a}")" ); done

    local empty_stdin
    empty_stdin="$(mktemp)"
    JAVA_TOOL_OPTIONS="-Duser.language=en -Dorg.jline.terminal.provider=dumb" \
        sql -S -name "${conn}" @"$(sqlcl_to_win "${script}")" "${args[@]}" \
            < "${empty_stdin}" 2>&1 \
        | grep -v 'Picked up JAVA_TOOL_OPTIONS'
    local rc="${PIPESTATUS[0]}"
    rm -f "${empty_stdin}"
    return "${rc}"
}
