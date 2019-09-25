#l vim:ft=zsh

which sqlite3 >/dev/null 2>&1 || return;

typeset -g __ZHIST_DIR="${(%):-%N}"
__ZHIST_DIR="${__ZHIST_DIR%/*}"

typeset -g __ZHIST_FILE="${HOME}/.zsh-history${LOGIN_ID}.db"
typeset -g __ZHIST_PID_FILE="${__ZHIST_DIR}/.zsh-history${LOGIN_ID}.pid"
typeset -g __ZHIST_INPUT_PIPE="${__ZHIST_DIR}/.zsh-history${LOGIN_ID}.pipe"
typeset -g __ZHIST_REGISTERED_SHELLS="${__ZHIST_DIR}/.zsh-history${LOGIN_ID}.shells"

typeset -g __ZHIST_SESSION __ZHIST_QUERY_LOG __ZHIST_PIPE_FD
typeset -gi __ZHIST_RAN_CMD __ZHIST_DAEMON_PID

typeset -ga __ZHIST_IGNORE_COMMANDS
__ZHIST_IGNORE_COMMANDS=("^ls$" "^cd$" "^ " "^zhist" "^$")

if [[ -n "$ZHIST_ENABLE_LOG" && "$ZHIST_ENABLE_LOG" == 1 ]]; then
  __ZHIST_QUERY_LOG="${HOME}/.zsh-history${LOGIN_ID}.log"
else
  __ZHIST_QUERY_LOG="/dev/null"
fi

SEP=$'\x1f'

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
    echo "$$" >> "${__ZHIST_REGISTERED_SHELLS}"
  fi

}

__zhist_check () {

  if  [[ ! -s "${__ZHIST_FILE}" ]]; then
    __zhist_createdb;
    __zhist_daemon_stop;
  fi

  if [[ ! -e "${__ZHIST_INPUT_PIPE}" ]]; then
    if [[ -n "${__ZHIST_PIPE_FD}" ]]; then
      exec {__ZHIST_PIPE_FD}>&-
      unset "${__ZHIST_PIPE_FD}"
    fi
    __zhist_daemon_stop;
    mkfifo "${__ZHIST_INPUT_PIPE}"
    chmod 600 "${__ZHIST_INPUT_PIPE}";
  fi

  if [[ -z "${__ZHIST_PIPE_FD}" ]]; then
    exec {__ZHIST_PIPE_FD}<> "${__ZHIST_INPUT_PIPE}"
  fi

  if ! print -nu "${__ZHIST_PIPE_FD}" ; then
    unset "${__ZHIST_PIPE_FD}" 2> /dev/null
    exec {__ZHIST_PIPE_FD}<> "${__ZHIST_INPUT_PIPE}"
	fi

  if ! __zhist_daemon_check; then
    __zhist_daemon_start;
  fi

}

__zhist_createdb () {

  if [[ -s "${HOME}/.zsh-history.db" ]]; then
    mv "${HOME}/.zsh-history.db" "${HOME}/.zsh-history${LOGIN_ID}.db"
    return;
  fi

  mkdir -p "$(dirname "${__ZHIST_FILE}")"

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

  if [[ -w "${__ZHIST_REGISTERED_SHELLS}" ]]; then

    sed -i "/^$$\$/d" "${__ZHIST_REGISTERED_SHELLS}"

    if [[ ! -s "${__ZHIST_REGISTERED_SHELLS}" ]]; then
      __zhist_daemon_stop;
      rm "${__ZHIST_INPUT_PIPE}" &> /dev/null
      rm "${__ZHIST_REGISTERED_SHELLS}" &> /dev/null
    fi

  fi

}

__zhist_query () {

  sqlite3 -header -separator "$SEP" "${__ZHIST_FILE}" "$@"

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

  sqlite3 "${__ZHIST_FILE}" <&"${__ZHIST_PIPE_FD}" &!

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

  if [[ -z "$__ZHIST_DAEMON_PID" ]]; then
    read -rt __ZHIST_DAEMON_PID < "${__ZHIST_PID_FILE}"
  fi

  if [[ -z "$__ZHIST_DAEMON_PID" ]]; then
    return 1;
  fi

  if ! \kill -0 "${__ZHIST_DAEMON_PID}" &> /dev/null ; then

    # If pid isn't running, double check pid value in case it was changed by another shell
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

  fi

  __ZHIST_RAN_CMD=0

}

__zhist_insert_start() {

  local cmd;

  __zhist_check || return;

  cmd="${1}"

  for boring in "${__ZHIST_IGNORE_COMMANDS[@]}"; do
    if [[ "$cmd" =~ $boring ]]; then
      return
    fi
  done

  __ZHIST_RAN_CMD=1

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

}

__zhist_init
