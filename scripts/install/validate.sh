#!/usr/bin/env bash

# 安装校验能力
# 负责依赖检查、安装路径校验以及安装流程退出辅助

# 校验安装依赖命令是否齐全
_valid_required() {
    local required_cmds=("xz" "pgrep" "curl" "tar" "unzip" "gzip" "shuf" "sed" "awk" "grep")
    local missing=()
    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" >&/dev/null || missing+=("$cmd")
    done
    command -v ss >&/dev/null || command -v netstat >&/dev/null || missing+=("ss/netstat")
    command -v ip >&/dev/null || command -v hostname >&/dev/null || missing+=("ip/hostname")
    [ "${#missing[@]}" -gt 0 ] && _error_quit "请先安装以下命令：${missing[*]}"
    return 0
}

# 安装路径、执行 shell 与依赖总校验
_valid() {
    _valid_required

    [ -d "$CLASH_BASE_DIR" ] && _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"

    local msg="${CLASH_BASE_DIR}：当前路径不可用，请在 .env 中更换安装路径。"
    mkdir -p "$CLASH_BASE_DIR" || _error_quit "$msg"
    _is_regular_sudo && [[ $CLASH_BASE_DIR == /root* ]] && _error_quit "$msg"

    [ -z "${ZSH_VERSION:-}" ] && [ -z "${BASH_VERSION:-}" ] && _error_quit "仅支持：bash、zsh 执行"
    return 0
}

# 生成随机字符串，用于初始化 Web 密钥等场景
_get_random_val() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 6
}

# 退出安装流程，必要时先执行收尾命令
_quit() {
    [ "$#" -gt 0 ] && {
        "$@"
        _finish_context $?
    }
    _finish_context 0
}
