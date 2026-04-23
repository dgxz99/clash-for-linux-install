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

# Tun 以 root 方式运行时，普通用户不能直接卸载
pgrep -f "$BIN_KERNEL" -u 0 >/dev/null && ! _is_root && _error_quit "请先关闭 Tun 模式"

# 关闭服务并撤销安装时写入的系统集成
clashoff 2>/dev/null
_uninstall_service
_revoke_rc

# 清理自动更新任务
command -v crontab >&/dev/null && crontab -l | grep -v "clashsub" | crontab -

# 删除安装目录
/usr/bin/rm -rf "$CLASH_BASE_DIR"

echo '✨' '已卸载，相关配置已清除'
_quit
