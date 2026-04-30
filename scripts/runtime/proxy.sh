#!/usr/bin/env bash

# 代理控制能力
# 负责普通代理模式、系统代理、状态查看、控制台和升级相关能力

# 根据运行时配置导出系统代理变量
_set_system_proxy() {
    local runtime_path yq_bin
    runtime_path=$(_config_runtime_path)
    yq_bin=$(_yq_bin)
    local mixed_port=$("$yq_bin" '.mixed-port // ""' "$runtime_path")
    local http_port=$("$yq_bin" '.port // ""' "$runtime_path")
    local socks_port=$("$yq_bin" '.socks-port // ""' "$runtime_path")

    local auth=$("$yq_bin" '.authentication[0] // ""' "$runtime_path")
    [ -n "$auth" ] && auth=$auth@

    local bind_addr=$(_get_bind_addr)
    local http_proxy_addr="http://${auth}${bind_addr}:${http_port:-${mixed_port}}"
    local socks_proxy_addr="socks5h://${auth}${bind_addr}:${socks_port:-${mixed_port}}"
    local no_proxy_addr="localhost,127.0.0.1,::1"

    export http_proxy=$http_proxy_addr
    export HTTP_PROXY=$http_proxy

    export https_proxy=$http_proxy
    export HTTPS_PROXY=$https_proxy

    export all_proxy=$socks_proxy_addr
    export ALL_PROXY=$all_proxy

    export no_proxy=$no_proxy_addr
    export NO_PROXY=$no_proxy
}

# 清理当前 shell 中的系统代理变量
_unset_system_proxy() {
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset all_proxy
    unset ALL_PROXY
    unset no_proxy
    unset NO_PROXY
}

# 启动代理环境
function clashon() {
    _bootstrap_runtime
    _detect_proxy_port
    clashstatus >&/dev/null || placeholder_start
    clashstatus >&/dev/null || {
        _failcat '启动失败: 执行 clashlog 查看日志'
        return 1
    }
    clashproxy >/dev/null && _set_system_proxy
    _okcat '已开启代理环境'
}

# 在交互 shell 首次加载时按需自动开启代理
watch_proxy() {
    _bootstrap_runtime
    [ -z "$http_proxy" ] && {
        [[ $- == *i* ]] && {
            placeholder_watch_proxy
        }
    }
}

# 关闭代理环境
function clashoff() {
    _bootstrap_runtime
    clashstatus >&/dev/null && {
        placeholder_stop >/dev/null
        clashstatus >&/dev/null && _tunstatus >&/dev/null && {
            _tunoff || _error_quit "请先关闭 Tun 模式"
        }
        placeholder_stop >/dev/null
        clashstatus >&/dev/null && {
            _failcat '代理环境关闭失败'
            return 1
        }
    }
    _unset_system_proxy
    _okcat '已关闭代理环境'
}

# 重启代理环境
clashrestart() {
    _bootstrap_runtime
    clashoff >/dev/null
    clashon
}

# 查看或切换系统代理状态
function clashproxy() {
    _bootstrap_runtime
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看系统代理状态
  clashproxy

- 开启系统代理
  clashproxy on

- 关闭系统代理
  clashproxy off

EOF
        return 0
        ;;
    on)
        clashstatus >&/dev/null || {
            _failcat "$KERNEL_NAME 未运行，请先执行 clashon"
            return 1
        }
        "$(_yq_bin)" -i '._custom.system-proxy.enable = true' "$(_config_mixin_path)"
        _set_system_proxy
        _okcat '已开启系统代理'
        ;;
    off)
        "$(_yq_bin)" -i '._custom.system-proxy.enable = false' "$(_config_mixin_path)"
        _unset_system_proxy
        _okcat '已关闭系统代理'
        ;;
    *)
        local system_proxy_enable=$("$(_yq_bin)" '._custom.system-proxy.enable' "$(_config_mixin_path)" 2>/dev/null)
        case $system_proxy_enable in
        true)
            _okcat "系统代理：开启
$(env | grep -i 'proxy=')"
            ;;
        *)
            _failcat "系统代理：关闭"
            ;;
        esac
        ;;
    esac
}

# 查看内核运行状态，兼容普通模式与 Tun 模式
function clashstatus() {
    _bootstrap_runtime
    placeholder_is_active >&/dev/null && {
        placeholder_status "$@"
        return 0
    }
    _tunstatus >&/dev/null && {
        placeholder_sudo_status "$@"
        return 0
    }
    placeholder_status "$@"
    return 1
}

# 查看运行日志
function clashlog() {
    _bootstrap_runtime
    placeholder_is_active >&/dev/null || {
        _tunstatus >&/dev/null && {
            placeholder_sudo_log "$@"
            return 0
        }
    }
    placeholder_log "$@"
}

# 输出 Web 控制台访问地址
function clashui() {
    _bootstrap_runtime
    _detect_ext_addr
    clashstatus >&/dev/null || clashon >/dev/null
    local query_url='api64.ipify.org'
    local public_ip=$(curl -s --noproxy "*" --location --max-time 2 $query_url)
    local public_address="http://${public_ip:-公网}:${EXT_PORT}/ui"

    local local_ip=$EXT_IP
    local local_address="http://${local_ip}:${EXT_PORT}/ui"
    printf "\n"
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║                %s                  ║\n" "$(_okcat 'Web 控制台')"
    printf "║═══════════════════════════════════════════════║\n"
    printf "║                                               ║\n"
    printf "║     🔓 注意放行端口：%-5s                    ║\n" "$EXT_PORT"
    printf "║     🏠 内网：%-31s  ║\n" "$local_address"
    printf "║     🌏 公网：%-31s  ║\n" "$public_address"
    printf "║     ☁️  公共：%-31s  ║\n" "$URL_CLASH_UI"
    printf "║                                               ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"
}

# 合并配置后重启内核使其生效
_merge_config_restart() {
    local tun_active=0
    _tunstatus >&/dev/null && tun_active=1
    _merge_config
    placeholder_stop >/dev/null
    ((tun_active)) && {
        _sudo_restart
        sleep 0.1
        return 0
    }
    placeholder_stop >/dev/null
    sleep 0.1
    placeholder_start >/dev/null
    sleep 0.1
}

# 查看或修改 Web 控制台密钥
function clashsecret() {
    _bootstrap_runtime
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Web 密钥
  clashsecret

- 修改 Web 密钥
  clashsecret <new_secret>

EOF
        return 0
        ;;
    esac

    case $# in
    0)
        _okcat "当前密钥：$(_get_secret)"
        ;;
    1)
        [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || {
            _failcat "密钥仅支持字母、数字、点、下划线和短横线"
            return 1
        }
        "$(_yq_bin)" -i ".secret = \"$1\"" "$(_config_mixin_path)" || {
            _failcat "密钥更新失败，请重新输入"
            return 1
        }
        _merge_config_restart
        _okcat "密钥更新成功，已重启生效"
        ;;
    *)
        _failcat "密钥不要包含空格或使用引号包围"
        ;;
    esac
}

# 触发内核自升级
function clashupgrade() {
    _bootstrap_runtime
    for arg in "$@"; do
        case $arg in
        -h | --help)
            cat <<EOF
Usage:
  clashupgrade [OPTIONS]

Options:
  -v, --verbose       输出内核升级日志
  -r, --release       升级至稳定版
  -a, --alpha         升级至测试版
  -h, --help          显示帮助信息

EOF
            return 0
            ;;
        -v | --verbose)
            local log_flag=true
            ;;
        -r | --release)
            channel="release"
            ;;
        -a | --alpha)
            channel="alpha"
            ;;
        *)
            channel=""
            ;;
        esac
    done

    _detect_ext_addr
    clashstatus >&/dev/null || clashon >/dev/null
    _okcat '⏳' "请求内核升级..."
    [ "$log_flag" = true ] && {
        log_cmd=(placeholder_follow_log)
        ("${log_cmd[@]}" &)
    }
    local res=$(
        curl -X POST \
            --silent \
            --noproxy "*" \
            --location \
            -H "Authorization: Bearer $(_get_secret)" \
            "http://${EXT_IP}:${EXT_PORT}/upgrade?channel=$channel"
    )
    [ "$log_flag" = true ] && pkill -9 -f "${log_cmd[*]}"

    grep '"status":"ok"' <<<"$res" && {
        _okcat "内核升级成功"
        return 0
    }
    grep 'already using latest version' <<<"$res" && {
        _okcat "已是最新版本"
        return 0
    }
    _failcat "内核升级失败，请检查网络或稍后重试"
}
