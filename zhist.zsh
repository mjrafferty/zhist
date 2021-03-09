#l vim:ft=zsh

which sqlite3 >/dev/null 2>&1 || return;

typeset -g __ZHIST_DIR="${(%):-%N}"
__ZHIST_DIR="${__ZHIST_DIR%/*}"

typeset -g __ZHIST_DB="${XDG_DATA_HOME:-$HOME}/zhist${LOGIN_ID}.db"

typeset -g __ZHIST_PID_FILE="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist${LOGIN_ID}.pid"
typeset -g __ZHIST_PIPE="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist${LOGIN_ID}.pipe"
typeset -g __ZHIST_SHELLS="${XDG_RUNTIME_DIR:-$__ZHIST_DIR}/zhist${LOGIN_ID}.shells"

typeset -g __ZHIST_SESSION __ZHIST_QUERY_LOG __ZHIST_PIPE_FD __ZHIST_RAN_CMD __ZHIST_DAEMON_PID

typeset -ga __ZHIST_IGNORE_COMMANDS
__ZHIST_IGNORE_COMMANDS=("^ls$" "^cd$" "^ " "^zhist" "^$")

if [[ -n "$ZHIST_ENABLE_LOG" && "$ZHIST_ENABLE_LOG" == 1 ]]; then
  __ZHIST_QUERY_LOG="${XDG_DATA_HOME:-$HOME}/zhist${LOGIN_ID}.log"
else
  __ZHIST_QUERY_LOG="/dev/null"
fi

__zhist_init() {

  setopt multios

  zmodload zsh/datetime

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec __zhist_insert_start
  add-zsh-hook precmd __zhist_insert_stop
  add-zsh-hook zshexit __zhist_exit

  fpath+="${__ZHIST_DIR}/functions"
  autoload -Uz zhist zhist-top

  __zhist_session_id

  if [[ -w "${__ZHIST_DIR}" ]]; then
    echo "$$" >> "${__ZHIST_SHELLS}"
  fi

}

__zhist_check () {

  if  [[ ! -s "${__ZHIST_DB}" ]]; then
    __zhist_createdb;
    __zhist_daemon_stop;
  fi

  if [[ ! -e "${__ZHIST_PIPE}" ]]; then
    __zhist_daemon_stop;
    mkfifo "${__ZHIST_PIPE}"
    chmod 600 "${__ZHIST_PIPE}";
  fi

  exec {__ZHIST_PIPE_FD}<> "${__ZHIST_PIPE}"

  if ! print -nu "${__ZHIST_PIPE_FD}" ; then
    unset "${__ZHIST_PIPE_FD}" 2> /dev/null
    exec {__ZHIST_PIPE_FD}<> "${__ZHIST_PIPE}"
  fi

  if ! __zhist_daemon_check; then
    __zhist_daemon_start;
  fi

}

__zhist_createdb () {

  if [[ -s "${XDG_DATA_HOME:-$HOME}/zhist.db" ]]; then
    mv "${XDG_DATA_HOME:-$HOME}/zhist.db" "${__ZHIST_DB}"
    return;
  fi

  mkdir -p "$(dirname "${__ZHIST_DB}")"

  __zhist_query <<- EOF
  CREATE TABLE commands (
    id integer primary key autoincrement,
    argv TEXT,
    UNIQUE(argv) ON CONFLICT IGNORE
  );
  CREATE TABLE places (
    id integer primary key autoincrement,
    host TEXT,
    dir TEXT,
    UNIQUE(host, dir) ON CONFLICT IGNORE
  );
  CREATE TABLE users (
    id integer primary key autoincrement,
    user TEXT,
    UNIQUE(user) ON CONFLICT IGNORE
  );
  CREATE TABLE history (
    id integer primary key autoincrement,
    session int,
    command_id int REFERENCES commands (id),
    place_id int REFERENCES places (id),
    user_id int REFERENCES users (id),
    exit_status INT,
    start_time INT,
    duration INT
  );
EOF

}

__zhist_exit () {

  if [[ -w "${__ZHIST_SHELLS}" ]]; then

    sed -i "/^$$\$/d" "${__ZHIST_SHELLS}"

    if [[ ! -s "${__ZHIST_SHELLS}" ]]; then
      __zhist_daemon_stop;
      rm "${__ZHIST_PIPE}" &> /dev/null
      rm "${__ZHIST_SHELLS}" &> /dev/null
    fi

  fi

}

__zhist_query () {

  local sep=$'\x1f'

  sqlite3 -header -separator "$sep" "${__ZHIST_DB}" "$@"

  if [[ "$?" -ne 0 ]]; then
    echo "error in $*";
  fi

}

__zhist_session_id() {

  local i length random
  local -a chars

  zmodload -i zsh/mathfunc

  __ZHIST_SESSION=""

  length=6
  chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  while (( i++ < length )); do
    random=$((1 + int( ${(c)#chars} * rand48() ) ))
    __ZHIST_SESSION+="$chars[$random]"
    chars[$random]=""
  done

}

__zhist_daemon_start () {

  __zhist_daemon_stop;

  sqlite3 "${__ZHIST_DB}" <&"${__ZHIST_PIPE_FD}" &!

  __ZHIST_DAEMON_PID="$!"

  echo "${__ZHIST_DAEMON_PID}" >| "${__ZHIST_PID_FILE}"
  chmod 600 "$__ZHIST_PID_FILE";

}

__zhist_daemon_stop () {

  if [[ -n "${__ZHIST_DAEMON_PID}" ]]; then
    \kill "$__ZHIST_DAEMON_PID" &> /dev/null
    unset "${__ZHIST_DAEMON_PID}"
  fi

  if [[ -e "${__ZHIST_PID_FILE}" ]]; then
    rm "${__ZHIST_PID_FILE}" &> /dev/null
  fi

}

__zhist_daemon_check() {

  if [[ ! -s "${__ZHIST_PID_FILE}" ]]; then
    return 1;
  fi

  # If this user doesnt have write perms, dont try to manage daemon
  if [ ! -w "${__ZHIST_PID_FILE}" ]; then
    return 0;
  fi

  if [[ -z "$__ZHIST_DAEMON_PID" ]]; then
    read -rt __ZHIST_DAEMON_PID < "${__ZHIST_PID_FILE}"
  fi

  if [[ -z "$__ZHIST_DAEMON_PID" ]]; then
    return 1;
  fi

  if ! \kill -0 "${__ZHIST_DAEMON_PID}" &> /dev/null ; then

    # If pid isnt running, double check pid value in case it was changed by another shell
    read -rt __ZHIST_DAEMON_PID < "${__ZHIST_PID_FILE}"

    if ! \kill -0 "$__ZHIST_DAEMON_PID" &> /dev/null; then
      return 1;
    fi

  fi

  return 0;

}

__zhist_insert_stop () {

  local retval=$?

  if (( __ZHIST_RAN_CMD == 1 )); then

  __zhist_check || return;

    >&"$__ZHIST_PIPE_FD" >>! "$__ZHIST_QUERY_LOG" <<- EOF
  UPDATE history SET
  exit_status = ${retval},
  duration = ${EPOCHSECONDS} - start_time
  WHERE id = (
    SELECT MAX(id)
    FROM history
    WHERE session = "${__ZHIST_SESSION}"
    AND exit_status IS NULL
    AND duration IS NULL
  );
EOF

  exec {__ZHIST_PIPE_FD}>&-

  fi

  __ZHIST_RAN_CMD=0

}

__zhist_insert_start() {

  local cmd;

  cmd="${1}"

  for boring in "${__ZHIST_IGNORE_COMMANDS[@]}"; do
    if [[ "$cmd" =~ $boring ]]; then
      return
    fi
  done

  __ZHIST_RAN_CMD=1

  __zhist_check || return;

  cmd="${(S)cmd//'/''}"

  >&"$__ZHIST_PIPE_FD" >>! "$__ZHIST_QUERY_LOG" <<- EOF
  INSERT INTO commands (argv)
  VALUES ('${cmd}');
  INSERT INTO places (host, dir)
  VALUES ('$HOST', '${PWD}');
  INSERT INTO users (user)
  VALUES ('${USER}');
  INSERT INTO history (session, command_id, place_id, user_id, start_time)
  SELECT
    '${__ZHIST_SESSION}', commands.id, places.id, users.id, ${EPOCHSECONDS}
    FROM commands, places, users
    WHERE commands.argv = '${cmd}'
    AND places.host = '$HOST'
    AND users.user = '${USER}'
    AND places.dir = '${PWD}';
EOF

  exec {__ZHIST_PIPE_FD}>&-

}

__zhist_init
