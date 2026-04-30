#!/usr/bin/env bash

# Shell 集成能力
# 负责检测 shell 启动文件并注入 clashctl 命令入口

# 检测当前用户可写的 shell 启动文件
_detect_rc() {
    local home=$HOME
    RC_OWNER=
    SHELL_RC_BASH=
    SHELL_RC_ZSH=
    SHELL_RC_FISH=
    _is_regular_sudo && {
        home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)
        RC_OWNER=$SUDO_USER
    }

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

# 确保 sudo 安装时用户启动文件仍归原用户所有
_prepare_user_file() {
    local file=$1
    local dir
    [ -n "$file" ] || return 0
    dir=$(dirname "$file")
    [ -n "${RC_OWNER:-}" ] && {
        /usr/bin/install -d -o "$RC_OWNER" -g "$(id -gn "$RC_OWNER")" "$dir"
        touch "$file"
        chown "$RC_OWNER:$(id -gn "$RC_OWNER")" "$file"
        return 0
    }
    mkdir -p "$dir"
    touch "$file"
}

# 以目标用户身份追加 shell 启动片段
_append_user_file() {
    local file=$1
    [ -n "$file" ] || return 0
    _prepare_user_file "$file"
    [ -n "${RC_OWNER:-}" ] && {
        sudo -u "$RC_OWNER" tee -a "$file" >/dev/null
        return $?
    }
    tee -a "$file" >/dev/null
}

# 注入 clashctl 命令到 bash、zsh、fish
_apply_rc() {
    _detect_rc
    local clash_cmd_dir="${CLASH_BASE_DIR}/scripts/cmd"
    local source_clashctl=". ${clash_cmd_dir}/clashctl.sh"
    local rc
    _revoke_rc
    for rc in "$SHELL_RC_BASH" "$SHELL_RC_ZSH"; do
        [ -n "$rc" ] || continue
        _append_user_file "$rc" <<EOF

$start_flag
# 加载 clashctl 命令
$source_clashctl
# 新开 shell 时自动开启代理环境
# watch_proxy
$end_flag
EOF
    done
    [ -n "$SHELL_RC_FISH" ] && {
        local project_root fish_template
        project_root=$(_get_project_root)
        fish_template="${project_root}/scripts/cmd/clashctl.fish"
        _prepare_user_file "$SHELL_RC_FISH"
        /usr/bin/install -m 0644 "$fish_template" "$SHELL_RC_FISH"
        [ -n "${RC_OWNER:-}" ] && chown "$RC_OWNER:$(id -gn "$RC_OWNER")" "$SHELL_RC_FISH"
        sed -i "s#placeholder_clashctl_script#${clash_cmd_dir}/clashctl.sh#g" "$SHELL_RC_FISH"
        [ -n "${RC_OWNER:-}" ] && chown "$RC_OWNER:$(id -gn "$RC_OWNER")" "$SHELL_RC_FISH"
    }
    # shellcheck disable=SC1090
    . "${clash_cmd_dir}/clashctl.sh"
}

# 从 shell 启动文件中移除 clashctl 注入内容
_revoke_rc() {
    _detect_rc
    local rc
    for rc in "$SHELL_RC_BASH" "$SHELL_RC_ZSH"; do
        [ -f "$rc" ] || continue
        [ -n "${RC_OWNER:-}" ] && chown "$RC_OWNER:$(id -gn "$RC_OWNER")" "$rc"
        sed -i --follow-symlinks "/$start_flag/,/$end_flag/d" "$rc" 2>/dev/null
        [ -n "${RC_OWNER:-}" ] && chown "$RC_OWNER:$(id -gn "$RC_OWNER")" "$rc"
    done
    [ -n "$SHELL_RC_FISH" ] && rm -f "$SHELL_RC_FISH" 2>/dev/null
    return 0
}
