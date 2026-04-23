#!/usr/bin/env bash

# 环境加载器
# 负责按脚本所在根目录加载 .env，并初始化共享路径变量

_get_project_root() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    dirname "$(dirname "$script_dir")"
}

_load_env() {
    local root_dir
    root_dir=$(_get_project_root)
    local env_path="${root_dir}/.env"

    [ -f "$env_path" ] || {
        printf '未找到环境文件：%s\n' "$env_path" >&2
        return 1
    }

    # shellcheck disable=SC1090
    . "$env_path"

    KERNEL_NAME="${KERNEL_NAME:-mihomo}"
}

_init_install_context() {
    CLASH_RESOURCES_DIR="${CLASH_BASE_DIR}/resources"
    CLASH_CONFIG_BASE="${CLASH_RESOURCES_DIR}/config.yaml"
    CLASH_CONFIG_MIXIN="${CLASH_RESOURCES_DIR}/mixin.yaml"
    CLASH_CONFIG_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.yaml"
    CLASH_CONFIG_TUN_RUNTIME="${CLASH_RESOURCES_DIR}/runtime.tun.yaml"
    CLASH_CONFIG_TEMP="${CLASH_RESOURCES_DIR}/temp.yaml"

    BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
    BIN_KERNEL="${BIN_BASE_DIR}/${KERNEL_NAME}"
    BIN_YQ="${BIN_BASE_DIR}/yq"
    BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
    BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
    BIN_SUBCONVERTER_START="$BIN_SUBCONVERTER"
    BIN_SUBCONVERTER_STOP="pkill -9 -f $BIN_SUBCONVERTER"
    BIN_SUBCONVERTER_CONFIG="${BIN_SUBCONVERTER_DIR}/pref.yml"
    BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"

    CLASH_PROFILES_DIR="${CLASH_RESOURCES_DIR}/profiles"
    CLASH_PROFILES_META="${CLASH_RESOURCES_DIR}/profiles.yaml"
    CLASH_PROFILES_LOG="${CLASH_RESOURCES_DIR}/profiles.log"
}
