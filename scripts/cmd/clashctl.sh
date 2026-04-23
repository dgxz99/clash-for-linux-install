#!/usr/bin/env bash

# clashctl 主命令脚本
# 对外提供代理控制、Tun、订阅、日志和升级等操作入口

THIS_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE:-${(%):-%N}}")")
. "${THIS_SCRIPT_DIR}/../lib/env.sh"
. "${THIS_SCRIPT_DIR}/../lib/common.sh"
. "${THIS_SCRIPT_DIR}/../runtime/config.sh"
. "${THIS_SCRIPT_DIR}/../runtime/subscription.sh"
. "${THIS_SCRIPT_DIR}/../runtime/tun.sh"
. "${THIS_SCRIPT_DIR}/../runtime/proxy.sh"
. "${THIS_SCRIPT_DIR}/../runtime/profiles.sh"

_bootstrap_runtime() {
    [ "${_CLASH_RUNTIME_READY:-0}" = 1 ] && return 0
    _load_env
    _CLASH_RUNTIME_READY=1
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
