#!/usr/bin/env bash

# 订阅管理能力
# 负责订阅列表维护、切换、更新和日志记录

# 订阅管理总入口
function clashsub() {
    _bootstrap_runtime
    case "$1" in
    add)
        shift
        _sub_add "$@"
        ;;
    del)
        shift
        _sub_del "$@"
        ;;
    list | ls | '')
        shift
        _sub_list "$@"
        ;;
    use)
        shift
        _sub_use "$@"
        ;;
    update)
        shift
        _sub_update "$@"
        ;;
    log)
        shift
        _sub_log "$@"
        ;;
    -h | --help | *)
        cat <<EOF
clashsub - Clash 订阅管理工具

Usage: 
  clashsub COMMAND [OPTIONS]

Commands:
  add <url>       添加订阅
  ls              查看订阅
  del <id>        删除订阅
  use <id>        使用订阅
  update [id]     更新订阅
  log             订阅日志

Options:
  update:
    --auto        配置自动更新
    --convert     使用订阅转换
EOF
        ;;
    esac
}

# 新增订阅
_sub_add() {
    local url=$1
    [ -z "$url" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要添加的订阅链接：')"
        read -r url
        [ -z "$url" ] && _error_quit "订阅链接不能为空"
    }
    local exists_id
    exists_id=$(_get_id_by_url "$url" 2>/dev/null) && [ -n "$exists_id" ] &&
        _error_quit "该订阅链接已存在：[$exists_id]"

    local config_temp profiles_meta profile_dir yq_bin subconverter_log
    config_temp=$(_config_temp_path)
    profiles_meta=$(_profiles_meta_path)
    profile_dir=$(_profiles_dir)
    yq_bin=$(_yq_bin)
    subconverter_log=$(_subconverter_log_path)
    _download_config "$config_temp" "$url"
    _valid_config "$config_temp" || _error_quit "订阅无效，请检查：
    原始订阅：${config_temp}.raw
    转换订阅：$config_temp
    转换日志：$subconverter_log"

    local id=$("$yq_bin" '.profiles // [] | (map(.id) | max) // 0 | . + 1' "$profiles_meta")
    local profile_path="${profile_dir}/${id}.yaml"
    mv "$config_temp" "$profile_path"

    "$yq_bin" -i "
         .profiles = (.profiles // []) + 
         [{
           \"id\": $id,
           \"path\": \"$profile_path\",
           \"url\": \"$url\"
         }]
    " "$profiles_meta"
    _logging_sub "➕ 已添加订阅：[$id] $url"
    _okcat '🎉' "订阅已添加：[$id] $url"
}

# 删除订阅
_sub_del() {
    local id=$1
    [ -z "$id" ] && {
        echo -n "$(_okcat '✈️ ' '请输入要删除的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    _valid_profile_id "$id"
    local profile_path url use
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    use=$("$(_yq_bin)" '.use // ""' "$(_profiles_meta_path)")
    [ "$use" = "$id" ] && _error_quit "删除失败：订阅 $id 正在使用中，请先切换订阅"
    /usr/bin/rm -f "$profile_path"
    "$(_yq_bin)" -i "del(.profiles[] | select(.id == $id))" "$(_profiles_meta_path)"
    _logging_sub "➖ 已删除订阅：[$id] $url"
    _okcat '🎉' "订阅已删除：[$id] $url"
}

# 列出订阅元数据
_sub_list() {
    "$(_yq_bin)" "$(_profiles_meta_path)"
}

# 切换当前使用的订阅
_sub_use() {
    "$(_yq_bin)" -e '.profiles // [] | length == 0' "$(_profiles_meta_path)" >&/dev/null &&
        _error_quit "当前无可用订阅，请先添加订阅"
    local id=$1
    [ -z "$id" ] && {
        clashsub ls
        echo -n "$(_okcat '✈️ ' '请输入要使用的订阅 id：')"
        read -r id
        [ -z "$id" ] && _error_quit "订阅 id 不能为空"
    }
    _valid_profile_id "$id"
    local profile_path url
    profile_path=$(_get_path_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    url=$(_get_url_by_id "$id")
    cat "$profile_path" >"$(_config_base_path)"
    _merge_config_restart
    "$(_yq_bin)" -i ".use = $id" "$(_profiles_meta_path)"
    _logging_sub "🔥 订阅已切换为：[$id] $url"
    _okcat '🔥' '订阅已生效'
}

# 通过订阅 id 获取配置文件路径
_get_path_by_id() {
    _valid_profile_id "$1" || return 1
    "$(_yq_bin)" -e ".profiles[] | select(.id == $1) | .path" "$(_profiles_meta_path)" 2>/dev/null
}

# 通过订阅 id 获取原始订阅地址
_get_url_by_id() {
    _valid_profile_id "$1" || return 1
    "$(_yq_bin)" -e ".profiles[] | select(.id == $1) | .url" "$(_profiles_meta_path)" 2>/dev/null
}

# 通过订阅 URL 获取订阅 id
_get_id_by_url() {
    PROFILE_URL=$1 "$(_yq_bin)" -e '.profiles[] | select(.url == strenv(PROFILE_URL)) | .id' "$(_profiles_meta_path)" 2>/dev/null
}

# 校验订阅 id，避免拼接 yq 表达式时引入非法内容
_valid_profile_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || {
        _failcat "订阅 id 必须是数字：$1"
        return 1
    }
}

# 更新订阅，可选启用定时更新和强制转换
_sub_update() {
    local id='' is_convert=false
    while [ "$#" -gt 0 ]; do
        case $1 in
        --auto)
            command -v crontab >/dev/null || _error_quit "未检测到 crontab 命令，请先安装 cron 服务"
            crontab -l | grep -qs 'clashsub update' || {
                (
                    crontab -l 2>/dev/null
                    echo "0 0 */2 * * $SHELL -i -c 'clashsub update'"
                ) | crontab -
            }
            _okcat "已设置定时更新订阅"
            return 0
            ;;
        --convert)
            is_convert=true
            ;;
        -*)
            _error_quit "未知参数：$1"
            ;;
        *)
            [ -z "$id" ] || _error_quit "只能指定一个订阅 id"
            id=$1
            ;;
        esac
        shift
    done
    [ -z "$id" ] && id=$("$(_yq_bin)" '.use // 1' "$(_profiles_meta_path)")
    _valid_profile_id "$id"
    local url profile_path
    url=$(_get_url_by_id "$id") || _error_quit "订阅 id 不存在，请检查"
    profile_path=$(_get_path_by_id "$id")
    _okcat "✈️ " "更新订阅：[$id] $url"

    [ "$is_convert" = true ] && {
        _download_convert_config "$(_config_temp_path)" "$url"
    }
    [ "$is_convert" != true ] && {
        _download_config "$(_config_temp_path)" "$url"
    }
    _valid_config "$(_config_temp_path)" || {
        _logging_sub "❌ 订阅更新失败：[$id] $url"
        _error_quit "订阅无效：请检查：
    原始订阅：$(_config_temp_path).raw
    转换订阅：$(_config_temp_path)
    转换日志：$(_subconverter_log_path)"
    }
    _logging_sub "✅ 订阅更新成功：[$id] $url"
    cat "$(_config_temp_path)" >"$profile_path"
    local use
    use=$("$(_yq_bin)" '.use // ""' "$(_profiles_meta_path)")
    [ "$use" = "$id" ] && clashsub use "$use" && return
    _okcat '订阅已更新'
}

# 写入订阅操作日志
_logging_sub() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >>"$(_profiles_log_path)"
}

# 查看订阅操作日志
_sub_log() {
    tail <"$(_profiles_log_path)" "$@"
}
