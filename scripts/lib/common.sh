#!/usr/bin/env bash

# 通用工具函数
# 负责日志、进程/端口、shell 检测以及基础系统判断

_color_log() {
    local color=$1
    local msg=$2

    local hex="${color#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    local color_code="\033[38;2;${r};${g};${b}m"
    local reset_code="\033[0m"

    printf "%b%s%b\n" "$color_code" "$msg" "$reset_code"
}

_okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    _color_log "$color" "${emoji} $1"
    return 0
}

_failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    _color_log "$color" "${emoji} $1" >&2
    return 1
}

_is_interactive_shell_path() {
    local shell_name
    shell_name=$(basename "$1")
    case "$shell_name" in
    bash | zsh | fish | sh | dash | ash | ksh | mksh)
        return 0
        ;;
    esac
    return 1
}

_get_process_exec_path() {
    readlink -f "/proc/$1/exe" 2>/dev/null
}

_get_process_ppid() {
    awk '/^PPid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

_find_parent_interactive_shell() {
    local pid=$1
    local shell_path
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
        shell_path=$(_get_process_exec_path "$pid")
        [ -n "$shell_path" ] && _is_interactive_shell_path "$shell_path" && {
            echo "$shell_path"
            return 0
        }
        pid=$(_get_process_ppid "$pid")
    done
    return 1
}

_get_parent_interactive_shell() {
    _find_parent_interactive_shell "$PPID"
}

_get_interactive_shell() {
    local shell_path="${CLASH_SHELL:-}"
    [ -n "$shell_path" ] && {
        echo "$shell_path"
        return 0
    }

    shell_path=$(_get_parent_interactive_shell)
    [ -z "$shell_path" ] && shell_path="$SHELL"
    [ -z "$shell_path" ] && [ -n "$USER" ] &&
        shell_path=$(awk -F: -v user="$USER" '$1==user{print $7}' /etc/passwd)
    [ -n "$shell_path" ] || shell_path=/bin/sh
    echo "$shell_path"
}

_is_sourced_context() {
    local top_source_index=$(( ${#BASH_SOURCE[@]} - 1 ))
    [ "${BASH_SOURCE[$top_source_index]}" != "$0" ]
}

_finish_context() {
    local status=${1:-0}
    [ -n "${CLASH_NO_EXEC_SHELL:-}" ] && return "$status"
    _is_sourced_context && return "$status"
    exit "$status"
}

_error_quit() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        _color_log "$color" "${emoji} $1"
    }
    _finish_context 1
}

_is_port_used() {
    local port=$1
    { ss -tunl 2>/dev/null || netstat -tunl; } | grep -qs ":${port}\b"
}

_get_random_port() {
    local random_port
    random_port=$(shuf -i 1024-65535 -n 1)
    ! _is_port_used "$random_port" && {
        echo "$random_port"
        return 0
    }
    _get_random_port
}

_get_local_ip() {
    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$local_ip" ] && local_ip=$(hostname -I | awk '{print $1}')
    echo "$local_ip"
}

_set_env() {
    local key=$1
    local value=$2
    local env_path="${CLASH_BASE_DIR}/.env"

    grep -qE "^${key}=" "$env_path" && {
        value=${value//&/\\&}
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_path"
        return $?
    }
    echo "${key}=${value}" >>"$env_path"
}

_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_is_regular_sudo() {
    _is_root && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != 'root' ]
}
