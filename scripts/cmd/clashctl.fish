# fish shell 适配层
# 负责把 fish 调用转发给 bash 版本的 clashctl，并同步代理变量

set fn_arr \
clashui \
clashstatus \
clashsecret \
clashtun \
clashmixin \
clashsub \
clashlog \
clashupgrade \
clashhelp

set -gx fish_version $FISH_VERSION
set clashctl_bash_script "placeholder_clashctl_script"

# 解析 bash 输出中的代理变量同步标记
function __clashctl_parse_output
    for line in $argv
        if string match -q '__CLASH_ENV__*' -- $line
            set pair (string replace '__CLASH_ENV__' '' -- $line)
            set kv (string split -m 1 '=' -- $pair)
            set key $kv[1]
            set value $kv[2]

            if test -n "$value"
                set -gx $key $value
            else
                set -e $key
            end
            continue
        end

        echo $line
    end
end

# 执行 bash 版本的 clashctl 子命令
function __clashctl_bash
    set fn $argv[1]
    set -e argv[1]
    env CLASH_SHELL=(status fish-path) CLASH_NO_EXEC_SHELL=1 \
        bash -lc "source '$clashctl_bash_script'; $fn \"\$@\"" -- $argv
end

# 执行会修改代理环境的子命令，并把变量同步回 fish
function __clashctl_bash_sync_proxy
    set fn $argv[1]
    set -e argv[1]
    set output (
        env CLASH_SHELL=(status fish-path) CLASH_NO_EXEC_SHELL=1 \
            bash -lc "
                source '$clashctl_bash_script'
                $fn \"\$@\"
                status=\$?
                for key in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
                do
                    printf '__CLASH_ENV__%s=%s\n' \"\$key\" \"\${!key}\"
                done
                exit \$status
            " -- $argv
    )
    set cmd_status $status
    __clashctl_parse_output $output
    return $cmd_status
end

# 为只读类命令批量生成 fish 包装函数
for fn in $fn_arr
    eval "
    function $fn
        __clashctl_bash $fn \$argv
    end
    "
end


# fish 侧顶层命令入口
function clashctl
    if test -z "$argv"
        clashhelp
        return
    end


    set suffix $argv[1]
    set argv $argv[2..-1]

    switch $suffix
        case on
            clashon $argv
        case off
            clashoff $argv
        case proxy
            clashproxy $argv
        case '*'
            clash"$suffix" $argv
    end
end

# 需要同步代理变量的命令单独处理
function clashon
    __clashctl_bash_sync_proxy clashon $argv
end

function clashoff
    __clashctl_bash_sync_proxy clashoff $argv
end

function clashproxy
    switch $argv[1]
        case on
            __clashctl_bash_sync_proxy clashproxy on
        case off
            __clashctl_bash_sync_proxy clashproxy off
        case ''
            __clashctl_bash clashproxy
        case '*'
            __clashctl_bash clashproxy $argv
    end
end
