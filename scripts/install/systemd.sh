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
    service_src="${SCRIPT_INIT_DIR}/systemd.sh"
    service_mode=0644

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
        SYSTEMD_CAPABILITIES='CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE'
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

    service_sudo_start=(sudo sh -c '"nohup' "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '<' '/dev/null' '>' "$FILE_LOG" '2>\&1' '\&"')
    service_sudo_stop=($(_build_root_process_cmd stop))
    service_sudo_status=($(_build_root_process_cmd status))
    service_sudo_is_active=($(_build_root_process_cmd is_active))
    service_sudo_log=(sudo tail -n 200 "$FILE_LOG")

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

    local cmd_path="${BIN_KERNEL}"
    local cmd_arg="-d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"
    local cmd_full="${BIN_KERNEL} -d ${CLASH_RESOURCES_DIR} -f ${CLASH_CONFIG_RUNTIME}"

    [ -n "$service_src" ] && {
        mkdir -p "$(dirname "$service_target")"
        /usr/bin/install -D -m "${service_mode:-0755}" "$service_src" "$service_target"
        ((${#service_add[@]})) && "${service_add[@]}"
        sed -i \
            -e "s#placeholder_cmd_path#$cmd_path#g" \
            -e "s#placeholder_cmd_args#$cmd_arg#g" \
            -e "s#placeholder_cmd_full#$cmd_full#g" \
            -e "s#placeholder_log_file#$FILE_LOG#g" \
            -e "s#placeholder_pid_file#$FILE_PID#g" \
            -e "s#placeholder_kernel_name#$KERNEL_NAME#g" \
            -e "s#placeholder_kernel_desc#$kernel_desc#g" \
            -e "s#placeholder_systemd_capabilities#$SYSTEMD_CAPABILITIES#g" \
            -e "s#placeholder_wanted_by#$SYSTEMD_WANTED_BY#g" \
            "$service_target"
        [ -z "$SYSTEMD_CAPABILITIES" ] && sed -i \
            -e '/^CapabilityBoundingSet=$/d' \
            -e '/^AmbientCapabilities=$/d' \
            "$service_target"
    }
    sed -i \
        -e "s#placeholder_start#${service_start[*]}#g" \
        -e "s#placeholder_sudo_start#${service_sudo_start[*]}#g" \
        -e "s#placeholder_sudo_stop#${service_sudo_stop[*]}#g" \
        -e "s#placeholder_status#${service_status[*]}#g" \
        -e "s#placeholder_is_active#${service_is_active[*]}#g" \
        -e "s#placeholder_sudo_status#${service_sudo_status[*]}#g" \
        -e "s#placeholder_sudo_is_active#${service_sudo_is_active[*]}#g" \
        -e "s#placeholder_stop#${service_stop[*]}#g" \
        -e "s#placeholder_log#${service_log[*]}#g" \
        -e "s#placeholder_sudo_log#${service_sudo_log[*]}#g" \
        -e "s#placeholder_follow_log#${service_follow_log[*]}#g" \
        -e "s#placeholder_watch_proxy#${service_watch_proxy[*]}#g" \
        "$CLASH_CMD_DIR/clashctl.sh"

    "${service_enable[@]}" >&/dev/null && _okcat '🚀' '已设置开机自启'
    ((${#service_reload[@]})) && "${service_reload[@]}"
}

# 卸载服务文件并撤销开机自启
_uninstall_service() {
    _detect_init
    "${service_disable[@]}" >&/dev/null
    ((${#service_del[@]})) && "${service_del[@]}"
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
