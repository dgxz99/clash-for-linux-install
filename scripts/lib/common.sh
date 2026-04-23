#!/usr/bin/env bash

# 通用工具函数
# 负责日志、进程/端口以及基础系统判断

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

_is_root() {
    [ "$(id -u)" -eq 0 ]
}

_is_regular_sudo() {
    _is_root && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != 'root' ]
}
