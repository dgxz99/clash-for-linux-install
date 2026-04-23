#!/usr/bin/env bash

# 卸载入口脚本
# 负责关闭服务、移除 shell 注入、清理定时任务和安装目录

. scripts/lib/env.sh
. scripts/lib/common.sh
. scripts/install/validate.sh
. scripts/install/systemd.sh
. scripts/install/shell.sh
_load_env
_init_install_context
. "$CLASH_BASE_DIR/scripts/cmd/clashctl.sh" 2>/dev/null

# 校验当前用户是否允许执行卸载
_ensure_uninstall_allowed() {
    pgrep -f "$BIN_KERNEL" -u 0 >/dev/null && ! _is_root && _error_quit "请先关闭 Tun 模式"
}

# 卸载 systemd 服务与 shell 注入
_remove_integrations() {
    clashoff 2>/dev/null
    _uninstall_service
    _revoke_rc
}

# 清理自动更新任务
_cleanup_crontab() {
    command -v crontab >&/dev/null && crontab -l | grep -v "clashsub" | crontab -
}

# 删除安装目录
_remove_install_dir() {
    /usr/bin/rm -rf "$CLASH_BASE_DIR"
}

_ensure_uninstall_allowed
_remove_integrations
_cleanup_crontab
_remove_install_dir

echo '✨' '已卸载，相关配置已清除'
_quit
