#l vim:ft=zsh

which sqlite3 >/dev/null 2>&1 || return;

typeset -ga __ZHIST_IGNORE_COMMANDS
__ZHIST_IGNORE_COMMANDS=("^ls$" "^cd$" "^ " "^zhist" "^$")

typeset -gi __ZHIST_IDLE_TIMEOUT="${__ZHIST_IDLE_TIMEOUT:-900}"

typeset -g __ZHIST_DIR="${(%):-%N}"
__ZHIST_DIR="${__ZHIST_DIR%/*}"

typeset -g __ZHIST_HOST="${(%):-%m}"
typeset -g __ZHIST_DB="${XDG_DATA_HOME:-$HOME}/zhist-${DEV_MODE:-${__ZHIST_HOST}}.db"
typeset -g __ZHIST_PID_FILE="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist-${__ZHIST_HOST}.pid"
typeset -g __ZHIST_PIPE="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist-${__ZHIST_HOST}.pipe"
typeset -g __ZHIST_WATCH_FILE="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist-${__ZHIST_HOST}.watch"

typeset -g __ZHIST_SESSION __ZHIST_QUERY_LOG __ZHIST_PIPE_FD __ZHIST_RAN_CMD __ZHIST_WATCHER_PID

if [[ -n "$ZHIST_ENABLE_LOG" && "$ZHIST_ENABLE_LOG" == 1 ]]; then
  __ZHIST_QUERY_LOG="${XDG_DATA_HOME:-$HOME}/zhist${LOGIN_ID:+-$LOGIN_ID}.log"
else
  __ZHIST_QUERY_LOG="/dev/null"
fi

setopt multios

zmodload zsh/datetime

autoload -Uz add-zsh-hook
add-zsh-hook preexec __zhist_insert_start
add-zsh-hook precmd __zhist_insert_stop

fpath+="${__ZHIST_DIR}/functions"

autoload -Uz zhist zhist-top __zhist_createdb  __zhist_insert_start  \
  __zhist_insert_stop  __zhist_query  __zhist_session_id  __zhist_watcher  \
  __zhist_watcher_check  __zhist_watcher_start  __zhist_watcher_stop

__zhist_session_id

__zhist_watcher_check

unfunction __zhist_session_id
