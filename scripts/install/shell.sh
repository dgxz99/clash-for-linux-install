#!/usr/bin/env bash

# Shell 集成能力
# 负责检测 shell 启动文件并注入 clashctl 命令入口

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
