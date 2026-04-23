#!/usr/bin/env bash

# 安装前置逻辑
# 负责环境校验、二进制下载、服务脚本生成以及 shell 集成

RESOURCES_BASE_DIR="$CLASH_RESOURCES_DIR"

# 项目脚本目录
SCRIPT_BASE_DIR='scripts'
SCRIPT_INIT_DIR="${SCRIPT_BASE_DIR}/init"
SCRIPT_CMD_DIR="${SCRIPT_BASE_DIR}/cmd"
SCRIPT_CMD_FISH="${SCRIPT_CMD_DIR}/clashctl.fish"

# 安装后的命令脚本目录
CLASH_CMD_DIR="${CLASH_BASE_DIR}/$SCRIPT_CMD_DIR"

# 默认日志与 pid 文件位置
FILE_LOG="/var/log/${KERNEL_NAME}.log"
FILE_PID="/run/${KERNEL_NAME}.pid"
TEMP_ROOT_DIR=
TEMP_BASE_DIR=
TEMP_DOWNLOAD_DIR=
TEMP_EXTRACT_DIR=

# 校验安装依赖命令是否齐全
_valid_required() {
    local required_cmds=("xz" "pgrep" "curl" "tar" 'unzip')
    local missing=()
    for cmd in "${required_cmds[@]}"; do
        command -v "$cmd" >&/dev/null || missing+=("$cmd")
    done
    [ "${#missing[@]}" -gt 0 ] && _error_quit "请先安装以下命令：${missing[*]}"
}

# 安装路径、执行 shell 与依赖总校验
_valid() {
    _valid_required

    [ -d "$CLASH_BASE_DIR" ] && _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"

    local msg="${CLASH_BASE_DIR}：当前路径不可用，请在 .env 中更换安装路径。"
    mkdir -p "$CLASH_BASE_DIR" || _error_quit "$msg"
    _is_regular_sudo && [[ $CLASH_BASE_DIR == /root* ]] && _error_quit "$msg"

    [ -z "$ZSH_VERSION" ] && [ -z "$BASH_VERSION" ] && _error_quit "仅支持：bash、zsh 执行"
}

# 根据所选内核准备需要的压缩包并解压到安装目录
_prepare_zip() {
    _init_temp_dir
    trap '_cleanup_temp_dir' EXIT
    local required_zips=("mihomo" "yq" "subconverter" "ui")

    _download_zip "${required_zips[@]}"

    ZIP_KERNEL="$ZIP_MIHOMO"
    BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
    _unzip_zip
    _cleanup_temp_dir
    trap - EXIT
}

# 初始化安装过程使用的临时目录
_init_temp_dir() {
    TEMP_ROOT_DIR="$(pwd)/tmp"
    mkdir -p "$TEMP_ROOT_DIR" || _error_quit "无法创建安装临时根目录：$TEMP_ROOT_DIR"
    TEMP_BASE_DIR=$(mktemp -d "${TEMP_ROOT_DIR}/${KERNEL_NAME}-install.XXXXXX") ||
        _error_quit "无法创建安装临时目录"
    TEMP_DOWNLOAD_DIR="${TEMP_BASE_DIR}/download"
    TEMP_EXTRACT_DIR="${TEMP_BASE_DIR}/extract"
    mkdir -p "$TEMP_DOWNLOAD_DIR" "$TEMP_EXTRACT_DIR"
}

# 清理安装过程中的临时目录
_cleanup_temp_dir() {
    [ -n "${TEMP_BASE_DIR:-}" ] && [ -d "$TEMP_BASE_DIR" ] && rm -rf "$TEMP_BASE_DIR"
    [ -n "${TEMP_ROOT_DIR:-}" ] && [ -d "$TEMP_ROOT_DIR" ] && rmdir "$TEMP_ROOT_DIR" 2>/dev/null || true
    TEMP_ROOT_DIR=
    TEMP_BASE_DIR=
    TEMP_DOWNLOAD_DIR=
    TEMP_EXTRACT_DIR=
}

# 获取 x86_64 平台对应的 mihomo 优化等级
_get_x86_64_optimization_level() {
    local flags=$(grep -m1 '^flags' /proc/cpuinfo)
    local level=v1
    grep -qw sse4_2 <<<"$flags" && grep -qw popcnt <<<"$flags" && level=v2
    grep -qw avx2 <<<"$flags" && grep -qw fma <<<"$flags" && level=v3
    echo "$level"
}

# 通过 GitHub releases/latest 跳转解析仓库最新 tag
_resolve_latest_release_tag() {
    local repo=$1
    local name=${2:-$repo}
    local fallback_version=${3:-}
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local request_url="${URL_GH_API_PROXY:+${URL_GH_API_PROXY%/}/}${api_url}"
    local response
    local latest_tag

    _okcat '⏳' "正在获取 ${name} 最新版本信息..." >&2

    response=$(
        curl \
            --silent \
            --show-error \
            --fail \
            --insecure \
            --location \
            --retry 1 \
            -H 'Accept: application/vnd.github+json' \
            "$request_url"
    ) || {
        [ -n "$fallback_version" ] && {
            _failcat '⚠️ ' "获取 ${name} 最新版本失败，回退到默认版本：$fallback_version"
            echo "$fallback_version"
            return 0
        }
        _error_quit "无法获取 ${name} 最新版本，请检查网络或 API 代理"
    }

    latest_tag=$(
        printf '%s\n' "$response" |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
    )

    [[ "$latest_tag" =~ ^v[0-9] ]] || {
        [ -n "$fallback_version" ] && {
            _failcat '⚠️ ' "解析 ${name} 最新版本失败，回退到默认版本：$fallback_version"
            echo "$fallback_version"
            return 0
        }
        _error_quit "无法解析 ${name} 最新版本"
    }

    _okcat '✅' "获取到 ${name} 最新版本：$latest_tag" >&2
    echo "$latest_tag"
}

# 根据 release 资产名称构建 GitHub 下载地址
_build_github_release_download_url() {
    local repo=$1
    local version=$2
    local asset_name=$3
    echo "https://github.com/${repo}/releases/download/${version}/${asset_name}"
}

# 根据架构构建 mihomo 下载地址
_build_mihomo_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        local level=$(_get_x86_64_optimization_level)
        asset_name="mihomo-linux-amd64-${level}-${version}.gz"
        ;;
    *86*)
        asset_name="mihomo-linux-386-${version}.gz"
        ;;
    armv*)
        asset_name="mihomo-linux-armv7-${version}.gz"
        ;;
    aarch64)
        asset_name="mihomo-linux-arm64-${version}.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "MetaCubeX/mihomo" "$version" "$asset_name"
}

# 根据架构构建 yq 下载地址
_build_yq_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        asset_name="yq_linux_amd64.tar.gz"
        ;;
    *86*)
        asset_name="yq_linux_386.tar.gz"
        ;;
    armv*)
        asset_name="yq_linux_arm.tar.gz"
        ;;
    aarch64)
        asset_name="yq_linux_arm64.tar.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "mikefarah/yq" "$version" "$asset_name"
}

# 根据架构构建 subconverter 下载地址
_build_subconverter_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        asset_name="subconverter_linux64.tar.gz"
        ;;
    *86*)
        asset_name="subconverter_linux32.tar.gz"
        ;;
    armv*)
        asset_name="subconverter_armv7.tar.gz"
        ;;
    aarch64)
        asset_name="subconverter_aarch64.tar.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "tindy2013/subconverter" "$version" "$asset_name"
}

# 构建 zashboard 下载地址
_build_ui_download_url() {
    local version=$1
    _build_github_release_download_url "Zephyruso/zashboard" "$version" "dist.zip"
}

# 按 CPU 架构下载所需二进制资源
_download_zip() {
    (($#)) || return 0
    local url_mihomo url_yq url_subconverter url_ui
    local arch=$(uname -m)
    local level=''
    VERSION_MIHOMO=$(_resolve_latest_release_tag "MetaCubeX/mihomo" "mihomo" "${VERSION_MIHOMO:-}")
    VERSION_YQ=$(_resolve_latest_release_tag "mikefarah/yq" "yq" "${VERSION_YQ:-}")
    VERSION_SUBCONVERTER=$(_resolve_latest_release_tag "tindy2013/subconverter" "subconverter" "${VERSION_SUBCONVERTER:-}")
    VERSION_UI=$(_resolve_latest_release_tag "Zephyruso/zashboard" "zashboard" "${VERSION_UI:-}")
    url_ui=$(_build_ui_download_url "$VERSION_UI")
    case "$arch" in
    x86_64)
        level=$(_get_x86_64_optimization_level)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    *86*)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    armv*)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    aarch64)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    *)
        _error_quit "未知的架构版本：$arch，请检查架构支持情况后重试"
        ;;
    esac

    local -A urls=(
        [mihomo]="$url_mihomo"
        [yq]="$url_yq"
        [subconverter]="$url_subconverter"
        [ui]="$url_ui"
    )

    local item target_zips=()
    _okcat '🖥️ ' "系统架构：$arch $level"
    for item in "$@"; do
        local url="${urls[$item]}"
        local proxy_url="${URL_GH_PROXY:+${URL_GH_PROXY%/}/}${url}"
        url="$proxy_url"
        _okcat '⏳' "正在下载：${item}：$url"
        local target="${TEMP_DOWNLOAD_DIR}/$(basename "$url")"
        curl \
            --progress-bar \
            --show-error \
            --fail \
            --insecure \
            --location \
            --retry 1 \
            --output "$target" \
            "$url"
        case "$item" in
        mihomo)
            ZIP_MIHOMO=$target
            ;;
        yq)
            ZIP_YQ=$target
            ;;
        subconverter)
            ZIP_SUBCONVERTER=$target
            ;;
        ui)
            ZIP_UI=$target
            ;;
        esac
        target_zips+=("$target")
    done
    _valid_zip "${target_zips[@]}"
}

# 校验下载到的压缩包是否完整可用
_valid_zip() {
    (($#)) || return 1
    local zip fail_zips=()
    for zip in "$@"; do
        gzip -tq "$zip" || unzip -tqq "$zip" || fail_zips+=("$zip")
    done

    ((${#fail_zips[@]})) && _error_quit "文件验证失败：${fail_zips[*]} 请检查网络后重试"
}

# 将压缩包中的二进制和前端资源释放到目标目录
_unzip_zip() {
    local temp_bin_dir="${TEMP_EXTRACT_DIR}/bin"
    local temp_ui_dir="${TEMP_EXTRACT_DIR}/ui"
    local temp_yq
    _valid_zip "$ZIP_KERNEL" "$ZIP_YQ" "$ZIP_SUBCONVERTER" "$ZIP_UI"
    mkdir -p "$temp_bin_dir" "$temp_ui_dir" "$BIN_BASE_DIR" "$CLASH_RESOURCES_DIR"

    gzip -dc "$ZIP_KERNEL" >"${temp_bin_dir}/${KERNEL_NAME}"
    /usr/bin/install -Dm755 "${temp_bin_dir}/${KERNEL_NAME}" "$BIN_KERNEL"

    tar -xf "$ZIP_YQ" -C "$temp_bin_dir"
    temp_yq=$(echo "${temp_bin_dir}"/yq_*)
    /usr/bin/install -Dm755 "$temp_yq" "$BIN_YQ"

    tar -xf "$ZIP_SUBCONVERTER" -C "$temp_bin_dir"
    mkdir -p "$BIN_SUBCONVERTER_DIR"
    /bin/cp -rf "${temp_bin_dir}/subconverter/." "$BIN_SUBCONVERTER_DIR"
    /bin/cp "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG"

    unzip -oqq "$ZIP_UI" -d "$temp_ui_dir" 2>/dev/null || tar -xf "$ZIP_UI" -C "$temp_ui_dir"
    /bin/cp -rf "${temp_ui_dir}/." "$RESOURCES_BASE_DIR"
}

# shellcheck disable=SC2206
# 检测当前系统适合使用的服务管理方式
_detect_init() {
    [ -z "$INIT_TYPE" ] && INIT_TYPE=$(readlink /proc/1/exe)
    grep -qsE "docker|kubepods|containerd|podman|lxc" /proc/1/cgroup && INIT_TYPE='nohup'

    _is_root || {
        FILE_LOG="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.log"
        FILE_PID="${CLASH_RESOURCES_DIR}/${KERNEL_NAME}.pid"
        _has_systemd_user && INIT_TYPE='systemd' || INIT_TYPE='nohup'
    }

    service_log=(less '<' $FILE_LOG)
    service_follow_log=(tail -f -n 0 $FILE_LOG)
    service_watch_proxy=(clashon)
    _is_regular_sudo && {
        service_watch_proxy=(_failcat "'未检测到代理变量，可执行 clashon 开启代理环境'")
        _SUDO=sudo
    }

    case "${INIT_TYPE}" in
    *systemd)
        if _is_root || _is_regular_sudo; then
            service_log=($_SUDO journalctl -u "$KERNEL_NAME")
        else
            service_log=(journalctl --user -u "$KERNEL_NAME")
        fi
        service_follow_log=("${service_log[@]}" -q -f -n 0)
        _systemd
        ;;
    *init)
        _sysvinit
        ;;
    *busybox)
        command -v openrc-init >&/dev/null && _openrc
        ;;
    *openrc*)
        _openrc
        ;;
    *runit)
        _runit
        ;;
    nohup | *)
        INIT_TYPE='nohup'
        _nohup
        ;;
    esac
    ((${#service_sudo_start[@]})) || service_sudo_start=("${service_start[@]}")
    ((${#service_sudo_stop[@]})) || service_sudo_stop=("${service_stop[@]}")
    ((${#service_sudo_status[@]})) || service_sudo_status=("${service_status[@]}")
    ((${#service_sudo_is_active[@]})) || service_sudo_is_active=("${service_is_active[@]}")
    ((${#service_sudo_log[@]})) || service_sudo_log=("${service_log[@]}")
    INIT_TYPE=$(basename "$INIT_TYPE")
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

# OpenRC 服务模板参数
_openrc() {
    service_src="${SCRIPT_INIT_DIR}/OpenRC.sh"
    service_target="/etc/init.d/$KERNEL_NAME"
    service_mode=0755

    service_enable=(rc-update add "$KERNEL_NAME" default)
    service_disable=(rc-update del "$KERNEL_NAME" default)

    service_start=(rc-service "$KERNEL_NAME" start)
    service_stop=(rc-service "$KERNEL_NAME" stop)
    service_restart=(rc-service "$KERNEL_NAME" restart)
    service_status=(rc-service "$KERNEL_NAME" status)
    service_is_active=(rc-service "$KERNEL_NAME" status)
}

# runit 服务模板参数
_runit() {
    service_src="${SCRIPT_INIT_DIR}/runit.sh"
    service_target="/etc/sv/${KERNEL_NAME}/run"
    service_mode=0755
    service_del=(rm -rf "/etc/sv/${KERNEL_NAME:-mihomo}")

    service_reload=(sleep 2)
    service_enable=(ln -s "$(dirname "$service_target")" "/etc/runit/runsvdir/default/${KERNEL_NAME}")
    service_disable=(rm -f "/etc/runit/runsvdir/current/${KERNEL_NAME}")

    service_start=(sv up "$KERNEL_NAME")
    service_stop=(sv down "$KERNEL_NAME")
    service_restart=(sv restart "$KERNEL_NAME")
    service_status=(sv status "$KERNEL_NAME")
    service_is_active=(sv status "$KERNEL_NAME" \| grep -qs '^run')
}

# SysVinit 服务模板参数
_sysvinit() {
    service_src="${SCRIPT_INIT_DIR}/SysVinit.sh"
    service_target="/etc/init.d/$KERNEL_NAME"
    service_mode=0755

    command -v chkconfig >&/dev/null && {
        service_add=(chkconfig --add "$KERNEL_NAME")
        service_del=(chkconfig --del "$KERNEL_NAME")

        service_enable=(chkconfig "$KERNEL_NAME" on)
        service_disable=(chkconfig "$KERNEL_NAME" off)
    }
    command -v update-rc.d >&/dev/null && {
        service_add=(update-rc.d "$KERNEL_NAME" defaults)
        service_del=(update-rc.d "$KERNEL_NAME" remove)

        service_enable=(update-rc.d "$KERNEL_NAME" enable)
        service_disable=(update-rc.d "$KERNEL_NAME" disable)
    }

    service_start=(service "$KERNEL_NAME" start)
    service_stop=(service "$KERNEL_NAME" stop)
    service_restart=(service "$KERNEL_NAME" restart)
    service_status=(service "$KERNEL_NAME" status)
    service_is_active=(service "$KERNEL_NAME" status)
}
# shellcheck disable=SC2206

# systemd 服务模板参数
_systemd() {
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

    INIT_TYPE='systemd-user'
    SYSTEMD_WANTED_BY='default.target'
    SYSTEMD_CAPABILITIES=''
}

# 无服务管理器场景下的 nohup 兜底方案
_nohup() {
    service_enable=(false)
    service_disable=(false)

    # 使用子 shell 启动，确保进程脱离终端
    service_start=('(' nohup "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '>' "$FILE_LOG" '2>\&1' '\&' ')')
    # sudo 启动：nohup 完全脱离终端，关闭所有标准流
    service_sudo_start=(sudo sh -c '"nohup' "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '<' '/dev/null' '>' "$FILE_LOG" '2>\&1' '\&"')
    service_sudo_stop=($(_build_root_process_cmd stop))
    service_status=(pgrep -fa "$BIN_KERNEL")
    service_is_active=(pgrep -fa "$BIN_KERNEL")
    service_sudo_status=($(_build_root_process_cmd status))
    service_sudo_is_active=($(_build_root_process_cmd is_active))
    service_sudo_log=(sudo tail -n 200 "$FILE_LOG")
    service_stop=(pkill -9 -f "$BIN_KERNEL")
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
        "$CLASH_CMD_DIR/clashctl.sh" "$CLASH_CMD_DIR/common.sh"

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

# 检测当前用户可写的 shell 启动文件
_detect_rc() {
    local home=$HOME
    _is_regular_sudo && home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)

    command -v bash >&/dev/null && {
        SHELL_RC_BASH="${home}/.bashrc"
    }
    command -v zsh >&/dev/null && {
        SHELL_RC_ZSH="${home}/.zshrc"
    }
    command -v fish >&/dev/null && {
        SHELL_RC_FISH="${home}/.config/fish/conf.d/clashctl.fish"
    }
    start_flag="# clashctl START"
    end_flag="# clashctl END"
}

# 注入 clashctl 命令到 bash、zsh、fish
_apply_rc() {
    _detect_rc
    local source_clashctl=". $CLASH_CMD_DIR/clashctl.sh"
    # shellcheck disable=SC2086
    tee -a "$SHELL_RC_BASH" $SHELL_RC_ZSH >/dev/null <<EOF

$start_flag
# 加载 clashctl 命令
$source_clashctl
# 新开 shell 时自动开启代理环境
# watch_proxy
$end_flag
EOF
    [ -n "$SHELL_RC_FISH" ] && {
        mkdir -p "$(dirname "$SHELL_RC_FISH")"
        /usr/bin/install "$SCRIPT_CMD_FISH" "$SHELL_RC_FISH"
        sed -i "s#placeholder_clashctl_script#${CLASH_CMD_DIR}/clashctl.sh#g" "$SHELL_RC_FISH"
    }
    $source_clashctl
}

# 从 shell 启动文件中移除 clashctl 注入内容
_revoke_rc() {
    _detect_rc
    sed -i --follow-symlinks "/$start_flag/,/$end_flag/d" "$SHELL_RC_BASH" "$SHELL_RC_ZSH" 2>/dev/null
    [ -n "$SHELL_RC_FISH" ] && rm -f "$SHELL_RC_FISH" 2>/dev/null
}

# 回写关键运行参数到安装目录内的 .env
_set_envs() {
    _set_env INIT_TYPE "$INIT_TYPE"
    _set_env KERNEL_NAME "$KERNEL_NAME"
    _set_env CLASH_BASE_DIR "$CLASH_BASE_DIR"
}

# 生成随机字符串，用于初始化 Web 密钥等场景
_get_random_val() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 6
}

# 判断是否处于 sudo 普通用户场景
_is_regular_sudo() {
    _is_root && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != 'root' ]
}

# 判断当前是否为 root
_is_root() {
    [ "$(id -u)" -eq 0 ]
}

# 退出安装流程，必要时先执行收尾命令
_quit() {
    local cmd="$*"
    [ -n "$cmd" ] && {
        eval "$cmd"
        _finish_context $?
    }
    _finish_context 0
}
