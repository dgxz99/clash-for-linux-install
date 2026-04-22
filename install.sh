#!/usr/bin/env bash

# 加载公共函数与变量定义
. scripts/cmd/clashctl.sh
. scripts/preflight.sh

# 安装前校验与参数解析
_valid
_parse_args "$@"

# 准备二进制资源并识别当前运行环境
_prepare_zip
_detect_init

_okcat "安装内核：$KERNEL_NAME by ${INIT_TYPE}"
_okcat '📦' "安装路径：$CLASH_BASE_DIR"

# 复制项目资源到安装目录并写入运行时环境
/bin/cp -rf . "$CLASH_BASE_DIR"
touch "$CLASH_CONFIG_BASE"
_set_envs
_is_regular_sudo && chown -R "$SUDO_USER" "$CLASH_BASE_DIR"

# 安装服务脚本并注入 shell 命令入口
_install_service
_apply_rc

# 生成运行时配置并输出控制台与密钥信息
_merge_config
_detect_proxy_port
clashui
clashsecret "$(_get_random_val)" >/dev/null
clashsecret

_okcat '🎉' 'enjoy 🎉'
clashctl

# 若基础配置已存在则自动作为第一个订阅导入
_valid_config "$CLASH_CONFIG_BASE" && CLASH_CONFIG_URL="file://$CLASH_CONFIG_BASE"
_quit "clashsub add $CLASH_CONFIG_URL && clashsub use 1"
