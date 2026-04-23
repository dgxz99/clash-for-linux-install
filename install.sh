#!/usr/bin/env bash

# 安装入口脚本
# 负责显式加载安装期与运行期依赖，并执行主安装流程

. scripts/lib/env.sh
. scripts/lib/common.sh
. scripts/install/validate.sh
. scripts/install/resources.sh
. scripts/install/systemd.sh
. scripts/install/shell.sh
_load_env
_init_install_context
. scripts/cmd/clashctl.sh

# 解析安装参数中的订阅链接
_parse_install_args() {
    for arg in "$@"; do
        case $arg in
        http*)
            CLASH_CONFIG_URL=$arg
            ;;
        esac
    done
}

# 准备资源并识别当前安装模式
_prepare_install_context() {
    _valid
    _parse_install_args "$@"
    _prepare_zip
    _detect_init

    _okcat "安装内核：$KERNEL_NAME by ${INIT_TYPE}"
    _okcat '📦' "安装路径：$CLASH_BASE_DIR"
}

# 复制仓库文件并回写安装运行环境
_copy_install_files() {
    /bin/cp -rf . "$CLASH_BASE_DIR"
    touch "$CLASH_CONFIG_BASE"
    _set_envs
    _is_regular_sudo && chown -R "$SUDO_USER" "$CLASH_BASE_DIR"
}

# 安装 systemd 服务与 shell 命令入口
_install_integrations() {
    _install_service
    _apply_rc
}

# 生成安装后的初始运行状态并展示入口信息
_finalize_install() {
    _merge_config
    _detect_proxy_port
    clashui
    clashsecret "$(_get_random_val)" >/dev/null
    clashsecret

    _okcat '🎉' 'enjoy 🎉'
    clashctl
}

# 若基础配置已存在则自动作为第一个订阅导入
_import_initial_profile() {
    _valid_config "$CLASH_CONFIG_BASE" && CLASH_CONFIG_URL="file://$CLASH_CONFIG_BASE"
    _quit "clashsub add $CLASH_CONFIG_URL && clashsub use 1"
}

_prepare_install_context "$@"
_copy_install_files
_install_integrations
_finalize_install
_import_initial_profile
