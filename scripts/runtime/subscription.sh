#!/usr/bin/env bash

# 订阅与转换能力
# 负责下载原始订阅、调用 subconverter 转换以及相关辅助逻辑

_download_config() {
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] || _okcat '⏳' '正在下载...'
    _download_raw_config "$dest" "$url" || return 1
    _okcat '🍃' '验证订阅配置...'
    _valid_config "$dest" || {
        _failcat '🍂' "验证失败：尝试订阅转换..."
        cat "$dest" >"${dest}.raw"
        _download_convert_config "$dest" "$url"
    }
}

_download_raw_config() {
    local dest=$1
    local url=$2

    curl \
        --silent \
        --show-error \
        --fail \
        --insecure \
        --location \
        --max-time 5 \
        --retry 1 \
        --user-agent "$CLASH_SUB_UA" \
        --output "$dest" \
        "$url" ||
        wget \
            --no-verbose \
            --no-check-certificate \
            --timeout 5 \
            --tries 1 \
            --user-agent "$CLASH_SUB_UA" \
            --output-document "$dest" \
            "$url"
}

_download_convert_config() {
    local dest=$1
    local url=$2
    local flag
    [ "${url:0:4}" = 'file' ] && return 0
    _start_convert
    local convert_url=$(
        target='clash'
        base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
        curl \
            --get \
            --silent \
            --show-error \
            --location \
            --output /dev/null \
            --data-urlencode "target=$target" \
            --data-urlencode "url=$url" \
            --write-out '%{url_effective}' \
            "$base_url"
    )
    curl --user-agent "$CLASH_SUB_UA" --silent --output "$dest" "$convert_url"
    flag=$?
    _stop_convert
    return $flag
}

_detect_subconverter_port() {
    BIN_SUBCONVERTER_PORT=$("$(_yq_bin)" '.server.port' "$(_subconverter_config_path)")
    _is_port_used "$BIN_SUBCONVERTER_PORT" && {
        local new_port=$(_get_random_port)
        _failcat '🎯' "端口冲突：[subconverter] ${BIN_SUBCONVERTER_PORT} 🎲 随机分配：$new_port"
        BIN_SUBCONVERTER_PORT=$new_port
        "$(_yq_bin)" -i ".server.port = $new_port" "$(_subconverter_config_path)" 2>/dev/null
    }
}

_start_convert() {
    _detect_subconverter_port
    local check_cmd="curl http://localhost:${BIN_SUBCONVERTER_PORT}/version"
    $check_cmd >&/dev/null && return 0
    ("$(_subconverter_bin)" >&"$(_subconverter_log_path)" &)
    local start
    start=$(date +%s)
    while ! $check_cmd >&/dev/null; do
        sleep 0.5s
        local now
        now=$(date +%s)
        [ $((now - start)) -gt 2 ] && _error_quit "订阅转换服务未启动，请检查日志：$(_subconverter_log_path)"
    done
}

_stop_convert() {
    pkill -9 -f "$(_subconverter_bin)" >/dev/null
}
