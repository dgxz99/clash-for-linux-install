#!/usr/bin/env bash

# clashctl 主命令脚本
# 对外提供代理控制、Tun、订阅、日志和升级等操作入口

THIS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE:-${(%):-%N}}")")
. "${THIS_SCRIPT_DIR}/../lib/env.sh"
. "${THIS_SCRIPT_DIR}/../lib/common.sh"
. "${THIS_SCRIPT_DIR}/../runtime/config.sh"
. "${THIS_SCRIPT_DIR}/../runtime/subscription.sh"

_bootstrap_runtime() {
    [ "${_CLASH_RUNTIME_READY:-0}" = 1 ] && return 0
    _load_env
    _CLASH_RUNTIME_READY=1
}

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
        # [[ "$0" == -* ]] && { # 登录式shell
        [[ $- == *i* ]] && { # 交互式shell
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
    local query_url='api64.ipify.org' # ifconfig.me
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

# 判断当前是否为 systemd-user 的 Tun 运行模式
_is_user_tun_mode() {
    [ "$INIT_TYPE" = 'systemd-user' ]
}

# 为 systemd-user 场景生成单独的 Tun 运行时配置
_prepare_user_tun_runtime() {
    local yq_bin mixin_path runtime_path tun_runtime_path
    yq_bin=$(_yq_bin)
    mixin_path=$(_config_mixin_path)
    runtime_path=$(_config_runtime_path)
    tun_runtime_path=$(_config_tun_runtime_path)
    "$yq_bin" -i '.tun.enable = true' "$mixin_path"
    _merge_config
    cat "$runtime_path" >"$tun_runtime_path"
    "$yq_bin" -i '.tun.enable = false' "$mixin_path"
    _merge_config
}

# 查询 Tun 状态
_tunstatus() {
    _is_user_tun_mode && {
        local tun_runtime_path
        tun_runtime_path=$(_config_tun_runtime_path)
        [ -f "$tun_runtime_path" ] || {
            _failcat 'Tun 状态：关闭'
            return 1
        }
        placeholder_sudo_is_active >&/dev/null && {
            _okcat 'Tun 状态：启用'
            return 0
        }
        rm -f "$tun_runtime_path"
        _failcat 'Tun 状态：关闭'
        return 1
    }
    local tun_status=$("$(_yq_bin)" '.tun.enable' "$(_config_runtime_path)")
    case $tun_status in
    true)
        _okcat 'Tun 状态：启用'
        ;;
    *)
        _failcat 'Tun 状态：关闭'
        ;;
    esac
}

# 关闭 Tun 模式
_tunoff() {
    _tunstatus >/dev/null || return 0
    placeholder_sudo_stop
    # 强制恢复终端输出处理
    stty opost 2>/dev/null
    _is_user_tun_mode && {
        rm -f "$(_config_tun_runtime_path)"
        "$(_yq_bin)" -i '.tun.enable = false' "$(_config_mixin_path)"
        _merge_config
    }
    clashstatus >&/dev/null || {
        _is_user_tun_mode || {
            "$(_yq_bin)" -i '.tun.enable = false' "$(_config_mixin_path)"
            _merge_config
        }
        clashon >/dev/null
        _okcat "Tun 模式已关闭"
        return 0
    }
    _tunstatus >&/dev/null && _failcat "Tun 模式关闭失败"
}

# 以 sudo 权限重启 Tun 相关进程
_sudo_restart() {
    placeholder_sudo_stop
    if _is_user_tun_mode; then
        local resources_dir tun_runtime_path tun_log kernel_bin
        resources_dir=$(_resources_dir)
        tun_runtime_path=$(_config_tun_runtime_path)
        kernel_bin=$(_kernel_bin)
        _prepare_user_tun_runtime
        tun_log="${resources_dir}/${KERNEL_NAME}.log"
        sudo sh -c "nohup \"$kernel_bin\" -d \"$resources_dir\" -f \"$tun_runtime_path\" < /dev/null > \"$tun_log\" 2>&1 &"
    else
        placeholder_sudo_start
    fi
    sleep 0.5
    # 强制恢复终端输出处理
    stty opost 2>/dev/null
}

# 开启 Tun 模式
_tunon() {
    _tunstatus 2>/dev/null && return 0
    placeholder_stop >/dev/null 2>&1
    placeholder_sudo_stop >/dev/null 2>&1
    if _is_user_tun_mode; then
        local resources_dir tun_runtime_path tun_log kernel_bin
        resources_dir=$(_resources_dir)
        tun_runtime_path=$(_config_tun_runtime_path)
        kernel_bin=$(_kernel_bin)
        _prepare_user_tun_runtime
        tun_log="${resources_dir}/${KERNEL_NAME}.log"
        sudo sh -c "nohup \"$kernel_bin\" -d \"$resources_dir\" -f \"$tun_runtime_path\" < /dev/null > \"$tun_log\" 2>&1 &"
    else
        "$(_yq_bin)" -i '.tun.enable = true' "$(_config_mixin_path)"
        _merge_config
        placeholder_sudo_start
    fi
    sleep 0.5
    # 强制恢复终端输出处理
    stty opost 2>/dev/null

    placeholder_sudo_is_active >&/dev/null || _error_quit "Tun 模式开启失败"
    local fail_msg="Start TUN listening error|unsupported kernel version"
    local ok_msg="Tun adapter listening at|TUN listening iface"
    clashlog | grep -E -m1 -qs "$fail_msg" && {
        [ "$KERNEL_NAME" = 'mihomo' ] && {
            "$(_yq_bin)" -i '.tun.auto-redirect = false' "$(_config_mixin_path)"
            _merge_config
            _sudo_restart
        }
        clashlog | grep -E -m1 -qs "$ok_msg" || {
            clashlog | grep -E -m1 "$fail_msg"
            _tunoff >&/dev/null
            _error_quit '系统内核版本不支持 Tun 模式'
        }
    }
    _okcat "Tun 模式已开启"
}

# Tun 子命令入口
function clashtun() {
    _bootstrap_runtime
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Tun 状态
  clashtun

- 开启 Tun 模式
  clashtun on

- 关闭 Tun 模式
  clashtun off
  
EOF
        return 0
        ;;
    on)
        _tunon
        ;;
    off)
        _tunoff
        ;;
    *)
        _tunstatus
        ;;
    esac
}

# 查看或编辑 mixin 配置
function clashmixin() {
    _bootstrap_runtime
    local mixin_path config_base runtime_path
    mixin_path=$(_config_mixin_path)
    config_base=$(_config_base_path)
    runtime_path=$(_config_runtime_path)
    case "$1" in
    -h | --help)
        cat <<EOF

- 查看 Mixin 配置：$mixin_path
  clashmixin

- 编辑 Mixin 配置
  clashmixin -e

- 查看原始订阅配置：$config_base
  clashmixin -c

- 查看运行时配置：$runtime_path
  clashmixin -r

EOF
        return 0
        ;;
    -e)
        vim "$mixin_path" && {
            _merge_config_restart && _okcat "配置更新成功，已重启生效"
        }
        ;;
    -r)
        less "$runtime_path"
        ;;
    -c)
        less "$config_base"
        ;;
    *)
        less "$mixin_path"
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

# 订阅管理总入口
function clashsub() {
    _bootstrap_runtime
    case "$1" in
    add)
        shift
        _sub_add "$@"
        ;;
    del)
        shift
        _sub_del "$@"
        ;;
    list | ls | '')
        shift
        _sub_list "$@"
        ;;
    use)
        shift
        _sub_use "$@"
        ;;
    update)
        shift
        _sub_update "$@"
        ;;
    log)
        shift
        _sub_log "$@"
        ;;
    -h | --help | *)
        cat <<EOF
clashsub - Clash 订阅管理工具

Usage: 
  clashsub COMMAND [OPTIONS]

Commands:
  add <url>       添加订阅
  ls              查看订阅
  del <id>        删除订阅
  use <id>        使用订阅
  update [id]     更新订阅
  log             订阅日志

Options:
  update:
    --auto        配置自动更新
    --convert     使用订阅转换
EOF
        ;;
    esac
}

# 新增订阅
_sub_add() {
    local url=$1
    [ -z "$url" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要添加的订阅链接：')"
        read -r url
        [ -z "$url" ] && _error_quit "订阅链接不能为空"
    }
    _get_url_by_id "$id" >/dev/null && _error_quit "该订阅链接已存在"

    local config_temp profiles_meta profile_dir yq_bin subconverter_log
    config_temp=$(_config_temp_path)
    profiles_meta=$(_profiles_meta_path)
    profile_dir=$(_profiles_dir)
    yq_bin=$(_yq_bin)
    subconverter_log=$(_subconverter_log_path)
    _download_config "$config_temp" "$url"
    _valid_config "$config_temp" || _error_quit "订阅无效，请检查：
    原始订阅：${config_temp}.raw
    转换订阅：$config_temp
    转换日志：$subconverter_log"

    local id=$("$yq_bin" '.profiles // [] | (map(.id) | max) // 0 | . + 1' "$profiles_meta")
    local profile_path="${profile_dir}/${id}.yaml"
    mv "$config_temp" "$profile_path"

    "$yq_bin" -i "
         .profiles = (.profiles // []) + 
         [{
           \"id\": $id,
           \"path\": \"$profile_path\",
           \"url\": \"$url\"
         }]
    " "$profiles_meta"
    _logging_sub "➕ 已添加订阅：[$id] $url"
    _okcat '🎉' "订阅已添加：[$id] $url"
}

# 删除订阅
_sub_del() {
    local id=$1
    [ -z "$id" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要删除的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    use=$("$(_yq_bin)" '.use // ""' "$(_profiles_meta_path)")
    [ "$use" = "$id" ] && _error_quit "删除失败：订阅 $id 正在使用中，请先切换订阅"
    /usr/bin/rm -f "$profile_path"
    "$(_yq_bin)" -i "del(.profiles[] | select(.id == \"$id\"))" "$(_profiles_meta_path)"
    _logging_sub "➖ 已删除订阅：[$id] $url"
    _okcat '🎉' "订阅已删除：[$id] $url"
}

# 列出订阅元数据
_sub_list() {
    "$(_yq_bin)" "$(_profiles_meta_path)"
}

# 切换当前使用的订阅
_sub_use() {
    "$(_yq_bin)" -e '.profiles // [] | length == 0' "$(_profiles_meta_path)" >&/dev/null &&
        _error_quit "当前无可用订阅，请先添加订阅"
    local id=$1
    [ -z "$id" ] && {
        clashsub ls
        echo -n "$(_okcat '✈️ ' '请输入要使用的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    cat "$profile_path" >"$(_config_base_path)"
    _merge_config_restart
    "$(_yq_bin)" -i ".use = $id" "$(_profiles_meta_path)"
    _logging_sub "🔥 订阅已切换为：[$id] $url"
    _okcat '🔥' '订阅已生效'
}

# 通过订阅 id 获取配置文件路径
_get_path_by_id() {
    "$(_yq_bin)" -e ".profiles[] | select(.id == \"$1\") | .path" "$(_profiles_meta_path)" 2>/dev/null
}

# 通过订阅 id 获取原始订阅地址
_get_url_by_id() {
    "$(_yq_bin)" -e ".profiles[] | select(.id == \"$1\") | .url" "$(_profiles_meta_path)" 2>/dev/null
}

# 更新订阅，可选启用定时更新和强制转换
_sub_update() {
    local arg is_convert
    for arg in "$@"; do
        case $arg in
        --auto)
            command -v crontab >/dev/null || _error_quit "未检测到 crontab 命令，请先安装 cron 服务"
            crontab -l | grep -qs 'clashsub update' || {
                (
                    crontab -l 2>/dev/null
                    echo "0 0 */2 * * $SHELL -i -c 'clashsub update'"
                ) | crontab -
            }
            _okcat "已设置定时更新订阅"
            return 0
            ;;
        --convert)
            is_convert=true
            shift
            ;;
        esac
    done
    local id=$1
    [ -z "$id" ] && id=$("$(_yq_bin)" '.use // 1' "$(_profiles_meta_path)")
    local url profile_path
    url=$(_get_url_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    profile_path=$(_get_path_by_id "$id")
    _okcat "✈️ " "更新订阅：[$id] $url"

    [ "$is_convert" = true ] && {
        _download_convert_config "$(_config_temp_path)" "$url"
    }
    [ "$is_convert" != true ] && {
        _download_config "$(_config_temp_path)" "$url"
    }
    _valid_config "$(_config_temp_path)" || {
        _logging_sub "❌ 订阅更新失败：[$id] $url"
        _error_quit "订阅无效：请检查：
    原始订阅：$(_config_temp_path).raw
    转换订阅：$(_config_temp_path)
    转换日志：$(_subconverter_log_path)"
    }
    _logging_sub "✅ 订阅更新成功：[$id] $url"
    cat "$(_config_temp_path)" >"$profile_path"
    use=$("$(_yq_bin)" '.use // ""' "$(_profiles_meta_path)")
    [ "$use" = "$id" ] && clashsub use "$use" && return
    _okcat '订阅已更新'
}

# 写入订阅操作日志
_logging_sub() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >>"$(_profiles_log_path)"
}

# 查看订阅操作日志
_sub_log() {
    tail <"$(_profiles_log_path)" "$@"
}

# clashctl 顶层命令分发
function clashctl() {
    _bootstrap_runtime
    case "$1" in
    on)
        shift
        clashon
        ;;
    off)
        shift
        clashoff
        ;;
    ui)
        shift
        clashui
        ;;
    status)
        shift
        clashstatus "$@"
        ;;
    log)
        shift
        clashlog "$@"
        ;;
    proxy)
        shift
        clashproxy "$@"
        ;;
    tun)
        shift
        clashtun "$@"
        ;;
    mixin)
        shift
        clashmixin "$@"
        ;;
    secret)
        shift
        clashsecret "$@"
        ;;
    sub)
        shift
        clashsub "$@"
        ;;
    upgrade)
        shift
        clashupgrade "$@"
        ;;
    *)
        (($#)) && shift
        clashhelp "$@"
        ;;
    esac
}

# 帮助信息输出
clashhelp() {
    _bootstrap_runtime
    cat <<EOF
    
Usage: 
  clashctl COMMAND [OPTIONS]

Commands:
  on                    开启代理
  off                   关闭代理
  proxy                 系统代理
  status                内核状态
  ui                    面板地址
  sub                   订阅管理
  log                   内核日志
  tun                   Tun 模式
  mixin                 Mixin 配置
  secret                Web 密钥
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息

For more help on how to use clashctl, head to https://github.com/dgxz99/clash-for-linux-install
EOF
}
