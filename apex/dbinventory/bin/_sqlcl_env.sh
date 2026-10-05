# ---------------------------------------------------------------------------
# _sqlcl_env.sh -- what every APEX script of this workspace needs to run SQLcl.
#
# To be sourced, not executed. Shared by validate.sh and post_import.sh, which
# used to carry identical copies of it.
#
# Why this is not fixtures/sqlcl.sh: that helper runs plain SQL and needs no
# JDK; the APEXlang compiler does. And the workspace tooling must not reach
# into fixtures/, which belongs to the schema side of the repository.
#
# The prerequisites handled here and by the callers -- do not drop them:
#
#   * JAVA_HOME must point at a JDK 17+. SQLcl ships/defaults to a JRE 11 on
#     the development machine, and oracle.apexlang.APEXLangCompiler is compiled
#     for class file version 61 -> UnsupportedClassVersionError otherwise.
#   * -Dorg.jline.terminal.provider=dumb. Under a captured (non-TTY) stdout
#     JLine cannot allocate a terminal on Windows: the ffm provider needs
#     --enable-native-access, and jansi/jna classes are absent.
#   * stdin must come from a real file. /dev/null and heredocs make SQLcl die
#     with "java.io.IOException: Fonction incorrecte" from System.in.available().
# ---------------------------------------------------------------------------

APEX_SQLCL_TOOL_OPTIONS="-Duser.language=en -Xmx800m -Dorg.jline.terminal.provider=dumb"

# SQLcl is a Windows process: it reads /g/... as C:\g\..., so hand it a
# Windows-resolvable path. cygpath -m keeps forward slashes (no escaping).
to_win() {
   if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

usable_jdk() { [[ -x "$1/bin/java.exe" || -x "$1/bin/java" ]]; }

# find_jdk -> prints the JDK to use, or nothing.
# In order of decreasing certainty. Do NOT hardcode a version here: the
# scripts used to pin C:/Program Files/Java/jdk-24, the machine was upgraded
# to 26, and they began failing with "no JDK" on a box that had one.
find_jdk() {
   local candidate
   for candidate in "${APEXLANG_JDK:-}" "${JAVA_HOME:-}"; do
      [[ -n "$candidate" ]] && usable_jdk "$candidate" && { printf '%s' "$candidate"; return; }
   done
   # Highest-numbered JDK under the usual install roots. Version sort, so
   # jdk-9 does not beat jdk-24.
   while IFS= read -r candidate; do
      usable_jdk "$candidate" && { printf '%s' "$candidate"; return; }
   done < <(ls -d "/c/Program Files/Java"/jdk-* "/usr/lib/jvm"/*jdk* 2>/dev/null | sort -V -r)
}

# resolve_app_dir <path> -> absolute path of an application directory, or an
# error. An application directory is one that holds an application.apx.
resolve_app_dir() {
   local dir
   if [[ -z "${1:-}" ]]; then
      echo "ERROR: missing application directory, e.g. ../applications/db-inv" >&2
      return 1
   fi
   dir="$(cd "$1" 2>/dev/null && pwd)" || { echo "ERROR: $1 is not a directory." >&2; return 1; }
   if [[ ! -f "$dir/application.apx" ]]; then
      echo "ERROR: $dir holds no application.apx; not an APEXlang application." >&2
      return 1
   fi
   printf '%s' "$dir"
}
