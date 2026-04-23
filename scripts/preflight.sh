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
