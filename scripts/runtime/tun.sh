#!/usr/bin/env bash

# Tun 能力
# 负责 Tun 运行时配置、状态切换和 systemd-user 下的 sudo 管理

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
