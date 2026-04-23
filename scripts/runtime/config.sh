#!/usr/bin/env bash

# 运行时配置能力
# 负责配置校验、端口检测、配置合并和 Web 控制台相关能力

_get_bind_addr() {
    local allow_lan bind_addr
    bind_addr=$("$BIN_YQ" '.bind-address // "*"' "$CLASH_CONFIG_RUNTIME")
    allow_lan=$("$BIN_YQ" '.allow-lan // false' "$CLASH_CONFIG_RUNTIME")

    case $allow_lan in
    true)
        [ "$bind_addr" = "*" ] && bind_addr=$(_get_local_ip)
        ;;
    false)
        bind_addr=127.0.0.1
        ;;
    esac
    echo "$bind_addr"
}

_detect_ext_addr() {
    local ext_addr
    ext_addr=$("$BIN_YQ" '.external-controller // ""' "$CLASH_CONFIG_RUNTIME")
    local ext_ip=${ext_addr%%:*}
    EXT_IP=$ext_ip
    EXT_PORT=${ext_addr##*:}
    [ "$ext_ip" = '0.0.0.0' ] && EXT_IP=$(_get_local_ip)
    _is_port_used "$EXT_PORT" && {
        curl -s --noproxy "*" -H "Authorization: Bearer $(_get_secret)" "127.0.0.1:${EXT_PORT}" | grep -qs "${KERNEL_NAME}" && return 0
        local new_port=$(_get_random_port)
        _failcat '🎯' "端口冲突：[external-controller] ${EXT_PORT} 🎲 随机分配 $new_port"
        EXT_PORT=$new_port
        "$BIN_YQ" -i ".external-controller = \"$ext_ip:$new_port\"" "$CLASH_CONFIG_MIXIN"
        _merge_config
    }
}

_valid_config() {
    local config=$1
    [[ ! -e "$config" || "$(wc -l <"$config")" -lt 1 ]] && return 1

    local test_cmd test_log
    test_cmd=("$BIN_KERNEL" -d "$(dirname "$config")" -f "$config" -t)
    test_log=$("${test_cmd[@]}") || {
        "${test_cmd[@]}"
        grep -qs "unsupport proxy type" <<<"$test_log" && {
            local prefix="检测到订阅中包含不受支持的代理协议"
            _error_quit "${prefix}, 请检查并升级内核版本"
        }
    }
}

_detect_proxy_port() {
    local mixed_port http_port socks_port
    mixed_port=$("$BIN_YQ" '.mixed-port // ""' "$CLASH_CONFIG_RUNTIME")
    http_port=$("$BIN_YQ" '.port // ""' "$CLASH_CONFIG_RUNTIME")
    socks_port=$("$BIN_YQ" '.socks-port // ""' "$CLASH_CONFIG_RUNTIME")
    [ -z "$mixed_port" ] && [ -z "$http_port" ] && [ -z "$socks_port" ] && mixed_port=7890

    local new_port count=0
    local port_list=(
        "mixed_port|mixed-port"
        "http_port|port"
        "socks_port|socks-port"
    )
    clashstatus >&/dev/null && local is_active=true
    for entry in "${port_list[@]}"; do
        local var_name="${entry%|*}"
        local yaml_key="${entry#*|}"

        eval "local var_val=\${$var_name}"

        [ -n "$var_val" ] && _is_port_used "$var_val" && [ "$is_active" != "true" ] && {
            new_port=$(_get_random_port)
            ((count++))
            _failcat '🎯' "端口冲突：[$yaml_key] $var_val 🎲 随机分配 $new_port"
            "$BIN_YQ" -i ".${yaml_key} = $new_port" "$CLASH_CONFIG_MIXIN"
        }
    done
    ((count)) && _merge_config
}

_merge_config() {
    cat "$CLASH_CONFIG_RUNTIME" >"$CLASH_CONFIG_TEMP" 2>/dev/null
    # shellcheck disable=SC2016
    "$BIN_YQ" eval-all '
      select(fileIndex==0) as $config |
      select(fileIndex==1) as $mixin |
      $mixin |= del(._custom) |
      (($config // {}) * $mixin) as $runtime |
      $runtime |
      .rules = (
        ($mixin.rules.prefix // []) +
        ($config.rules // []) +
        ($mixin.rules.suffix // [])
      ) |
      .proxies = (
        ($mixin.proxies.prefix // []) +
        (
          ($config.proxies // []) as $configList |
          ($mixin.proxies.override // []) as $overrideList |
          $configList | map(
            . as $configItem |
            (
              $overrideList[] | select(.name == $configItem.name)
            ) // $configItem
          )
        ) +
        ($mixin.proxies.suffix // [])
      ) |
      .proxy-groups = (
        ($mixin.proxy-groups.prefix // []) +
        (
          ($config.proxy-groups // []) as $configList |
          ($mixin.proxy-groups.override // []) as $overrideList |
          $configList | map(
            . as $configItem |
            (
              $overrideList[] | select(.name == $configItem.name)
            ) // $configItem
          )
        ) +
        ($mixin.proxy-groups.suffix // [])
      ) |
      ($mixin.proxy-groups.inject // {}) as $inj |
      .proxy-groups[] |= (
        . as $g |
        ($inj | .[$g.name] // []) as $extra |
        .proxies = (.proxies + $extra | unique)
      )
    ' "$CLASH_CONFIG_BASE" "$CLASH_CONFIG_MIXIN" >"$CLASH_CONFIG_RUNTIME"
    _valid_config "$CLASH_CONFIG_RUNTIME" || {
        cat "$CLASH_CONFIG_TEMP" >"$CLASH_CONFIG_RUNTIME"
        _error_quit "验证失败：请检查 Mixin 配置"
    }
}

_get_secret() {
    "$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME"
}
