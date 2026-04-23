#!/usr/bin/env bash

# 安装前置逻辑
# 负责环境校验、二进制下载、服务脚本生成以及 shell 集成

THIS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "${THIS_SCRIPT_DIR}/lib/env.sh"
. "${THIS_SCRIPT_DIR}/lib/common.sh"
. "${THIS_SCRIPT_DIR}/install/validate.sh"
. "${THIS_SCRIPT_DIR}/install/resources.sh"
. "${THIS_SCRIPT_DIR}/install/systemd.sh"
. "${THIS_SCRIPT_DIR}/install/shell.sh"
_load_env
_init_install_context

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
