#l vim:ft=zsh

which sqlite3 >/dev/null 2>&1 || return;

typeset -g __ZHIST_DIR="${(%):-%N}"
__ZHIST_DIR="${__ZHIST_DIR%/*}"

typeset -g __ZHIST_BIN="${__ZHIST_DIR}/bin"

typeset -g __ZHIST_HOST="${(%):-%m}"

typeset -ga __ZHIST_DEFAULT_IGNORE_COMMANDS
__ZHIST_DEFAULT_IGNORE_COMMANDS=("^ls$" "^cd$" "^ " "^zhist" "^$")

if [[ -z "$ZHIST_IGNORE_COMMANDS" ]]; then 
  ZHIST_IGNORE_COMMANDS=("${__ZHIST_DEFAULT_IGNORE_COMMANDS[@]}")
fi

typeset -gi __ZHIST_DEFAULT_IDLE_TIMEOUT=900
typeset -gi ZHIST_IDLE_TIMEOUT="${ZHIST_IDLE_TIMEOUT:-$__ZHIST_DEFAULT_IDLE_TIMEOUT}"

typeset -g __ZHIST_DEFAULT_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/zhist"
typeset -g ZHIST_DATA_DIR="${ZHIST_DATA_DIR:-$__ZHIST_DEFAULT_DATA_DIR}"

typeset -g __ZHIST_DEFAULT_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist"
typeset -g ZHIST_RUNTIME_DIR="${ZHIST_RUNTIME_DIR:-$__ZHIST_DEFAULT_RUNTIME_DIR}"

typeset -g __ZHIST_DEFAULT_DB="${ZHIST_DATA_DIR}/${DEV_MODE:-${__ZHIST_HOST}}.db"
typeset -g ZHIST_DB="${ZHIST_DB:-${__ZHIST_DEFAULT_DB}}"

typeset -g __ZHIST_PID_FILE="${ZHIST_RUNTIME_DIR}/${__ZHIST_HOST}.pid"
typeset -g __ZHIST_PIPE="${ZHIST_RUNTIME_DIR}/${__ZHIST_HOST}.pipe"
typeset -g __ZHIST_WATCH_FILE="${ZHIST_RUNTIME_DIR}/${__ZHIST_HOST}.watch"

typeset -g __ZHIST_SESSION __ZHIST_RAN_CMD __ZHIST_WATCHER_PID

typeset -g __ZHIST_DEFAULT_QUERY_LOG="${ZHIST_DATA_DIR}/zhist${LOGIN_ID:+-$LOGIN_ID}.log"

if [[ -n "$ZHIST_ENABLE_LOG" && "$ZHIST_ENABLE_LOG" == 1 ]]; then
  ZHIST_QUERY_LOG="${ZHIST_QUERY_LOG:-$__ZHIST_DEFAULT_QUERY_LOG}"
else
  ZHIST_QUERY_LOG="/dev/null"
fi

setopt multios

zmodload zsh/datetime

autoload -Uz add-zsh-hook
add-zsh-hook preexec __zhist_insert_start
add-zsh-hook precmd __zhist_insert_stop

fpath+="${__ZHIST_DIR}/functions"

autoload -Uz zhist zhist-top __zhist_insert_start _zhist_insert_stop  \
  __zhist_insert_query  __zhist_query  __zhist_session_id  __zhist_watcher  \
  __zhist_watcher_check  __zhist_watcher_start  __zhist_watcher_stop

mkdir -p "${ZHIST_DATA_DIR}" "${ZHIST_RUNTIME_DIR}" 2> /dev/null

__zhist_session_id
unfunction __zhist_session_id

__zhist_watcher_check

unset __ZHIST_DEFAULT_DB __ZHIST_DEFAULT_DATA_DIR __ZHIST_DEFAULT_RUNTIME_DIR \
  __ZHIST_DEFAULT_IDLE_TIMEOUT __ZHIST_DEFAULT_QUERY_LOG __ZHIST_DEFAULT_IGNORE_COMMANDS \
  __ZHIST_DIR __ZHIST_HOST
