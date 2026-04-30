#!/usr/bin/env bash

# systemd 安装能力
# 负责检测 systemd 模式、安装服务模板并回写安装参数

# shellcheck disable=SC2206
# 检测当前 systemd 服务模式
_detect_init() {
    [ -z "$INIT_TYPE" ] && INIT_TYPE=$(readlink /proc/1/exe)
    [[ "$INIT_TYPE" == *systemd ]] || _error_quit "当前项目仅支持 systemd / systemd --user"

    service_watch_proxy=(clashon)
    _is_regular_sudo && {
        service_watch_proxy=(_failcat "'未检测到代理变量，可执行 clashon 开启代理环境'")
        _SUDO=sudo
    }

    if _is_root || _is_regular_sudo; then
        service_log=($_SUDO journalctl -u "$KERNEL_NAME")
        service_follow_log=("${service_log[@]}" -q -f -n 0)
        _init_systemd_service
        ((${#service_sudo_start[@]})) || service_sudo_start=("${service_start[@]}")
        ((${#service_sudo_stop[@]})) || service_sudo_stop=("${service_stop[@]}")
        ((${#service_sudo_status[@]})) || service_sudo_status=("${service_status[@]}")
        ((${#service_sudo_is_active[@]})) || service_sudo_is_active=("${service_is_active[@]}")
        ((${#service_sudo_log[@]})) || service_sudo_log=("${service_log[@]}")
        INIT_TYPE='systemd'
        return 0
    fi

    FILE_LOG="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.log"
    FILE_PID="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.pid"
    _has_systemd_user || _error_quit "未检测到可用的 systemd --user 环境"
    service_log=(journalctl --user -u "$KERNEL_NAME")
    service_follow_log=("${service_log[@]}" -q -f -n 0)
    _init_systemd_service
    ((${#service_sudo_start[@]})) || service_sudo_start=("${service_start[@]}")
    ((${#service_sudo_stop[@]})) || service_sudo_stop=("${service_stop[@]}")
    ((${#service_sudo_status[@]})) || service_sudo_status=("${service_status[@]}")
    ((${#service_sudo_is_active[@]})) || service_sudo_is_active=("${service_is_active[@]}")
    ((${#service_sudo_log[@]})) || service_sudo_log=("${service_log[@]}")
    INIT_TYPE='systemd-user'
}

# systemd 服务参数
_init_systemd_service() {
    local project_root service_template
    project_root=$(_get_project_root)
    service_template="${project_root}/scripts/init/systemd.sh"
    service_src="$service_template"
    service_mode=0644
    FILE_LOG="/var/log/${KERNEL_NAME}.log"
    FILE_PID="/run/${KERNEL_NAME}.pid"

    if _is_root || _is_regular_sudo; then
        service_target="/etc/systemd/system/${KERNEL_NAME}.service"
        service_reload=($_SUDO systemctl daemon-reload)

        service_enable=($_SUDO systemctl enable "$KERNEL_NAME")
        service_disable=($_SUDO systemctl disable "$KERNEL_NAME")

        service_start=($_SUDO systemctl start "$KERNEL_NAME")
        service_stop=($_SUDO systemctl stop "$KERNEL_NAME")
        service_restart=($_SUDO systemctl restart "$KERNEL_NAME")
        service_status=($_SUDO systemctl status "$KERNEL_NAME")
        service_is_active=($_SUDO systemctl is-active "$KERNEL_NAME")
        service_sudo_start=("${service_start[@]}")
        service_sudo_stop=($_SUDO systemctl stop "$KERNEL_NAME")
        service_sudo_status=("${service_status[@]}")
        service_sudo_is_active=("${service_is_active[@]}")
        service_sudo_log=("${service_log[@]}")
        SYSTEMD_WANTED_BY='multi-user.target'
        SYSTEMD_CAPABILITIES='CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE'
        return 0
    fi

    service_target="${HOME}/.config/systemd/user/${KERNEL_NAME}.service"
    service_reload=(systemctl --user daemon-reload)

    service_enable=(systemctl --user enable "$KERNEL_NAME")
    service_disable=(systemctl --user disable "$KERNEL_NAME")

    service_start=(systemctl --user start "$KERNEL_NAME")
    service_stop=(systemctl --user stop "$KERNEL_NAME")
    service_restart=(systemctl --user restart "$KERNEL_NAME")
    service_status=(systemctl --user status "$KERNEL_NAME")
    service_is_active=(systemctl --user is-active "$KERNEL_NAME")

    service_sudo_start_cmd=$(_build_sudo_nohup_cmd "$BIN_KERNEL" "$CLASH_RESOURCES_DIR" "$CLASH_CONFIG_RUNTIME" "$FILE_LOG")
    service_sudo_stop_cmd=$(_build_root_process_cmd stop)
    service_sudo_status_cmd=$(_build_root_process_cmd status)
    service_sudo_is_active_cmd=$(_build_root_process_cmd is_active)
    service_sudo_log_cmd=$(_build_shell_cmd sudo tail -n 200 "$FILE_LOG")

    SYSTEMD_WANTED_BY='default.target'
    SYSTEMD_CAPABILITIES=''
}

# 为 systemd --user 场景补齐运行环境变量
_prepare_systemd_user_env() {
    [ -n "$XDG_RUNTIME_DIR" ] || {
        local runtime_dir="/run/user/$(id -u)"
        [ -d "$runtime_dir" ] && export XDG_RUNTIME_DIR="$runtime_dir"
    }
    [ -n "$DBUS_SESSION_BUS_ADDRESS" ] || {
        [ -n "$XDG_RUNTIME_DIR" ] && [ -S "$XDG_RUNTIME_DIR/bus" ] &&
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    }
}

# 构建需要 sudo 执行的进程控制命令
_build_root_process_cmd() {
    local action=$1
    case $action in
    stop)
        printf '%s' "sudo sh -c 'pkill -9 -f \"^\\\$1( |\\\$)\"' _ $(printf '%q' "$BIN_KERNEL")"
        ;;
    status | is_active)
        printf '%s' "sudo sh -c 'pgrep -fa \"^\\\$1( |\\\$)\"' _ $(printf '%q' "$BIN_KERNEL")"
        ;;
    esac
}

# 转义 sed 替换值，避免路径或命令中的特殊字符破坏模板渲染
_sed_replacement_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//&/\\&}
    value=${value//\#/\\#}
    printf '%s' "$value"
}

# 生成 systemd ExecStart 可安全识别的双引号参数
_systemd_quote() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"' "$value"
}

# 将命令参数拼接为可直接写入 bash 脚本的命令行
_build_shell_cmd() {
    local arg quoted cmd=''
    for arg in "$@"; do
        printf -v quoted '%q' "$arg"
        cmd="${cmd:+$cmd }$quoted"
    done
    printf '%s' "$cmd"
}

# 构建普通用户 Tun 场景下需要 sudo 执行的后台启动命令
_build_sudo_nohup_cmd() {
    local kernel_bin=$1
    local resources_dir=$2
    local runtime_path=$3
    local log_path=$4
    printf "sudo sh -c 'nohup \"\$1\" -d \"\$2\" -f \"\$3\" < /dev/null > \"\$4\" 2>&1 &' _ %s %s %s %s" \
        "$(_build_shell_cmd "$kernel_bin")" \
        "$(_build_shell_cmd "$resources_dir")" \
        "$(_build_shell_cmd "$runtime_path")" \
        "$(_build_shell_cmd "$log_path")"
}

# 判断当前用户是否可用 systemd --user
_has_systemd_user() {
    command -v systemctl >/dev/null 2>&1 || return 1
    _prepare_systemd_user_env
    [ -n "$XDG_RUNTIME_DIR" ] || return 1
    systemctl --user show-environment >/dev/null 2>&1
}

# 将模板渲染成实际服务文件，并回填到命令脚本占位符
_install_service() {
    local kernel_desc="$KERNEL_NAME Daemon, A[nother] Clash Kernel."
    local clash_cmd_dir="${CLASH_BASE_DIR}/scripts/cmd"

    local cmd_path="${BIN_KERNEL}"
    local cmd_arg="-d $(_systemd_quote "$CLASH_RESOURCES_DIR") -f $(_systemd_quote "$CLASH_CONFIG_RUNTIME")"
    local cmd_full="$(_systemd_quote "$BIN_KERNEL") -d $(_systemd_quote "$CLASH_RESOURCES_DIR") -f $(_systemd_quote "$CLASH_CONFIG_RUNTIME")"
    local placeholder_start placeholder_sudo_start placeholder_sudo_stop placeholder_status
    local placeholder_is_active placeholder_sudo_status placeholder_sudo_is_active
    local placeholder_stop placeholder_log placeholder_sudo_log placeholder_follow_log
    local placeholder_watch_proxy

    placeholder_start=$(_build_shell_cmd "${service_start[@]}")
    placeholder_sudo_start=${service_sudo_start_cmd:-$(_build_shell_cmd "${service_sudo_start[@]}")}
    placeholder_sudo_stop=${service_sudo_stop_cmd:-$(_build_shell_cmd "${service_sudo_stop[@]}")}
    placeholder_status=$(_build_shell_cmd "${service_status[@]}")
    placeholder_is_active=$(_build_shell_cmd "${service_is_active[@]}")
    placeholder_sudo_status=${service_sudo_status_cmd:-$(_build_shell_cmd "${service_sudo_status[@]}")}
    placeholder_sudo_is_active=${service_sudo_is_active_cmd:-$(_build_shell_cmd "${service_sudo_is_active[@]}")}
    placeholder_stop=$(_build_shell_cmd "${service_stop[@]}")
    placeholder_log=$(_build_shell_cmd "${service_log[@]}")
    placeholder_sudo_log=${service_sudo_log_cmd:-$(_build_shell_cmd "${service_sudo_log[@]}")}
    placeholder_follow_log=$(_build_shell_cmd "${service_follow_log[@]}")
    placeholder_watch_proxy=$(_build_shell_cmd "${service_watch_proxy[@]}")

    [ -n "$service_src" ] && {
        mkdir -p "$(dirname "$service_target")"
        /usr/bin/install -D -m "${service_mode:-0755}" "$service_src" "$service_target"
        declare -p service_add >/dev/null 2>&1 && ((${#service_add[@]})) && "${service_add[@]}"
        sed -i \
            -e "s#placeholder_cmd_path#$(_sed_replacement_escape "$cmd_path")#g" \
            -e "s#placeholder_cmd_args#$(_sed_replacement_escape "$cmd_arg")#g" \
            -e "s#placeholder_cmd_full#$(_sed_replacement_escape "$cmd_full")#g" \
            -e "s#placeholder_log_file#$(_sed_replacement_escape "$FILE_LOG")#g" \
            -e "s#placeholder_pid_file#$(_sed_replacement_escape "$FILE_PID")#g" \
            -e "s#placeholder_kernel_name#$(_sed_replacement_escape "$KERNEL_NAME")#g" \
            -e "s#placeholder_kernel_desc#$(_sed_replacement_escape "$kernel_desc")#g" \
            -e "s#placeholder_systemd_capabilities#$(_sed_replacement_escape "$SYSTEMD_CAPABILITIES")#g" \
            -e "s#placeholder_wanted_by#$(_sed_replacement_escape "$SYSTEMD_WANTED_BY")#g" \
            "$service_target"
        [ -z "$SYSTEMD_CAPABILITIES" ] && sed -i \
            -e '/^CapabilityBoundingSet=$/d' \
            -e '/^AmbientCapabilities=$/d' \
            "$service_target"
    }
    sed -i \
        -e "s#placeholder_start#$(_sed_replacement_escape "$placeholder_start")#g" \
        -e "s#placeholder_sudo_start#$(_sed_replacement_escape "$placeholder_sudo_start")#g" \
        -e "s#placeholder_sudo_stop#$(_sed_replacement_escape "$placeholder_sudo_stop")#g" \
        -e "s#placeholder_status#$(_sed_replacement_escape "$placeholder_status")#g" \
        -e "s#placeholder_is_active#$(_sed_replacement_escape "$placeholder_is_active")#g" \
        -e "s#placeholder_sudo_status#$(_sed_replacement_escape "$placeholder_sudo_status")#g" \
        -e "s#placeholder_sudo_is_active#$(_sed_replacement_escape "$placeholder_sudo_is_active")#g" \
        -e "s#placeholder_stop#$(_sed_replacement_escape "$placeholder_stop")#g" \
        -e "s#placeholder_log#$(_sed_replacement_escape "$placeholder_log")#g" \
        -e "s#placeholder_sudo_log#$(_sed_replacement_escape "$placeholder_sudo_log")#g" \
        -e "s#placeholder_follow_log#$(_sed_replacement_escape "$placeholder_follow_log")#g" \
        -e "s#placeholder_watch_proxy#$(_sed_replacement_escape "$placeholder_watch_proxy")#g" \
        "${clash_cmd_dir}/clashctl.sh"

    ((${#service_reload[@]})) && "${service_reload[@]}"
    "${service_enable[@]}" >&/dev/null && _okcat '🚀' '已设置开机自启'
}

# 卸载服务文件并撤销开机自启
_uninstall_service() {
    _detect_init
    "${service_disable[@]}" >&/dev/null
    declare -p service_del >/dev/null 2>&1 && ((${#service_del[@]})) && "${service_del[@]}"
    rm -f "$service_target"
    ((${#service_reload[@]})) && "${service_reload[@]}"
}

# 写入安装目录内的 .env 键值
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

# 回写关键运行参数到安装目录内的 .env
_set_envs() {
    _set_env INIT_TYPE "$INIT_TYPE"
    _set_env KERNEL_NAME "$KERNEL_NAME"
    _set_env CLASH_BASE_DIR "$CLASH_BASE_DIR"
}
