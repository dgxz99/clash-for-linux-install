#!/usr/bin/env bash
# shellcheck disable=SC2034

# 命令层公共能力
# 负责统一路径、日志输出、配置校验和订阅下载等底层逻辑

. "$(dirname "$(dirname "$THIS_SCRIPT_DIR")")/.env"

# 运行时配置文件路径
CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
CLASH_CONFIG_MIXIN="${CLASH_RESOURCES_DIR}/mixin.yaml"
CLASH_CONFIG_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.yaml"
CLASH_CONFIG_TUN_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.tun.yaml"
CLASH_CONFIG_TEMP="${CLASH_RESOURCES_DIR}/temp.yaml"

# 内核与辅助工具路径
BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
BIN_YQ="${BIN_BASE_DIR}/yq"
BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
BIN_SUBCONVERTER_START="$BIN_SUBCONVERTER"
BIN_SUBCONVERTER_STOP="pkill -9 -f $BIN_SUBCONVERTER"
BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"

CLASH_PROFILES_DIR="${CLASH_RESOURCES_DIR}/profiles"
CLASH_PROFILES_META="${CLASH_RESOURCES_DIR}/profiles.yaml"
CLASH_PROFILES_LOG="${CLASH_RESOURCES_DIR}/profiles.log"

# 检测端口是否已被占用
_is_port_used() {
    local port=$1
    { ss -tunl 2>/dev/null || netstat -tunl; } | grep -qs ":${port}\b"
}

# 获取一个当前未被占用的随机端口
_get_random_port() {
    local randomPort=$(shuf -i 1024-65535 -n 1)
    ! _is_port_used "$randomPort" && { echo "$randomPort" && return; }
    _get_random_port
}

# 结合 allow-lan 和 bind-address 推导实际监听地址
_get_bind_addr() {
    local allowLan bindAddr
    bindAddr=$("$BIN_YQ" '.bind-address // "*"' "$CLASH_CONFIG_RUNTIME")
    allowLan=$("$BIN_YQ" '.allow-lan // false' "$CLASH_CONFIG_RUNTIME")

    case $allowLan in
    true)
        [ "$bindAddr" = "*" ] && bindAddr=$(_get_local_ip)
        ;;
    false)
        bindAddr=127.0.0.1
        ;;
    esac
    echo "$bindAddr"
}

# 获取当前机器的局域网地址
_get_local_ip() {
    local local_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    [ -z "$local_ip" ] && local_ip=$(hostname -I | awk '{print $1}')
    echo "$local_ip"
}

# 检测外部控制器地址，必要时自动避开端口冲突
function _detect_ext_addr() {
    local ext_addr=$("$BIN_YQ" '.external-controller // ""' "$CLASH_CONFIG_RUNTIME")
    local ext_ip=${ext_addr%%:*}
    EXT_IP=$ext_ip
    EXT_PORT=${ext_addr##*:}
    [ "$ext_ip" = '0.0.0.0' ] && EXT_IP=$(_get_local_ip)
    _is_port_used "$EXT_PORT" && {
        curl -s --noproxy "*" -H "Authorization: Bearer $(_get_secret)" "127.0.0.1:${EXT_PORT}" | grep -qs "${KERNEL_NAME}" && return 0
        local newPort=$(_get_random_port)
        _failcat '🎯' "端口冲突：[external-controller] ${EXT_PORT} 🎲 随机分配 $newPort"
        EXT_PORT=$newPort
        "$BIN_YQ" -i ".external-controller = \"$ext_ip:$newPort\"" "$CLASH_CONFIG_MIXIN"
        _merge_config
    }
}

# 统一输出 24 位彩色日志
_color_log() {
    local color="$1"
    local msg="$2"

    local hex="${color#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    local color_code="\033[38;2;${r};${g};${b}m"
    local reset_code="\033[0m"

    printf "%b%s%b\n" "$color_code" "$msg" "$reset_code"
}

# 成功提示输出
function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg"
    return 0
}

# 失败提示输出
function _failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_log "$color" "$msg" >&2
    return 1
}

# 判断给定路径是否为可返回的交互 shell
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

# 读取指定进程对应的可执行文件路径
_get_process_exec_path() {
    readlink -f "/proc/$1/exe" 2>/dev/null
}

# 读取指定进程的父进程 pid
_get_process_ppid() {
    awk '/^PPid:/ {print $2}' "/proc/$1/status" 2>/dev/null
}

# 从指定 pid 开始沿父进程链查找交互 shell
_find_parent_interactive_shell() {
    local pid="$1"
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

# 沿父进程链查找发起当前脚本的交互 shell
_get_parent_interactive_shell() {
    _find_parent_interactive_shell "$PPID"
}

# 获取当前应当返回的交互 shell
_get_interactive_shell() {
    local shell_path="${CLASH_SHELL:-}"
    [ -n "$shell_path" ] && {
        echo "$shell_path"
        return 0
    }

    shell_path=$(_get_parent_interactive_shell)
    [ -z "$shell_path" ] && shell_path="$SHELL"
    [ -z "$shell_path" ] && [ -n "$USER" ] && shell_path=$(awk -F: -v user="$USER" '$1==user{print $7}' /etc/passwd)
    [ -n "$shell_path" ] || shell_path=/bin/sh
    echo "$shell_path"
}

# 判断当前函数是否运行在 source 进来的上下文中
_is_sourced_context() {
    local top_source_index=$(( ${#BASH_SOURCE[@]} - 1 ))
    [ "${BASH_SOURCE[$top_source_index]}" != "$0" ]
}

# 统一结束当前流程
_finish_context() {
    local status=${1:-0}
    [ -n "$CLASH_NO_EXEC_SHELL" ] && return "$status"
    _is_sourced_context && return "$status"
    exit "$status"
}

# 输出错误并结束当前流程
function _error_quit() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _color_log "$color" "$msg"
    }
    _finish_context 1
}

# 使用内核自检模式验证配置文件是否可用
function _valid_config() {
    local config="$1"
    [[ ! -e "$config" || "$(wc -l <"$config")" -lt 1 ]] && return 1

    local test_cmd test_log
    test_cmd=("$BIN_KERNEL" -d "$(dirname "$config")" -f "$config" -t)
    test_log=$("${test_cmd[@]}") || {
        "${test_cmd[@]}"
        grep -qs "unsupport proxy type" <<<"$test_log" && {
            local prefix="检测到订阅中包含不受支持的代理协议"
            [ "$KERNEL_NAME" = "clash" ] && _error_quit "${prefix}, 推荐安装使用 mihomo 内核"
            _error_quit "${prefix}, 请检查并升级内核版本"
        }
    }
}

# 下载订阅并在失败时自动尝试本地转换
function _download_config() {
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] || _okcat '⏳' '正在下载...'
    _download_raw_config "$dest" "$url" || return 1
    _okcat '🍃' '验证订阅配置...'
    _valid_config "$dest" || {
        _failcat '🍂' "验证失败：尝试订阅转换..."
        cat "$dest" >"${dest}.raw"
        _download_convert_config "$dest" "$url"
    }
}

# 直接下载原始订阅内容
_download_raw_config() {
    local dest=$1
    local url=$2

    curl \
        --silent \
        --show-error \
        --fail \
        --insecure \
        --location \
        --max-time 5 \
        --retry 1 \
        --user-agent "$CLASH_SUB_UA" \
        --output "$dest" \
        "$url" ||
        wget \
            --no-verbose \
            --no-check-certificate \
            --timeout 5 \
            --tries 1 \
            --user-agent "$CLASH_SUB_UA" \
            --output-document "$dest" \
            "$url"
}

# 通过 subconverter 将原始订阅转换为 clash 兼容配置
_download_convert_config() {
    local dest=$1
    local url=$2
    local flag
    [ "${url:0:4}" = 'file' ] && return 0
    _start_convert
    local convert_url=$(
        target='clash'
        base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
        curl \
            --get \
            --silent \
            --show-error \
            --location \
            --output /dev/null \
            --data-urlencode "target=$target" \
            --data-urlencode "url=$url" \
            --write-out '%{url_effective}' \
            "$base_url"
    )
    curl --user-agent "$CLASH_SUB_UA" --silent --output "$dest" "$convert_url"
    flag=$?
    _stop_convert
    return $flag
}

# 检测 subconverter 端口是否冲突
_detect_subconverter_port() {
    BIN_SUBCONVERTER_PORT=$("$BIN_YQ" '.server.port' "$BIN_SUBCONVERTER_CONFIG")
    _is_port_used "$BIN_SUBCONVERTER_PORT" && {
        local newPort=$(_get_random_port)
        _failcat '🎯' "端口冲突：[subconverter] ${BIN_SUBCONVERTER_PORT} 🎲 随机分配：$newPort"
        BIN_SUBCONVERTER_PORT=$newPort
        "$BIN_YQ" -i ".server.port = $newPort" "$BIN_SUBCONVERTER_CONFIG" 2>/dev/null
    }
}

# 拉起本地 subconverter 服务
_start_convert() {
    _detect_subconverter_port
    local check_cmd="curl http://localhost:${BIN_SUBCONVERTER_PORT}/version"
    $check_cmd >&/dev/null && return 0
    ("$BIN_SUBCONVERTER_START" >&"$BIN_SUBCONVERTER_LOG" &)
    local start=$(date +%s)
    while ! $check_cmd >&/dev/null; do
        sleep 0.5s
        local now=$(date +%s)
        [ $((now - start)) -gt 2 ] && _error_quit "订阅转换服务未启动，请检查日志：$BIN_SUBCONVERTER_LOG"
    done
}

# 停止本地 subconverter 服务
_stop_convert() {
    $BIN_SUBCONVERTER_STOP >/dev/null
}

# 更新安装目录中的 .env 键值
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
