#!/usr/bin/env bash

# 运行时配置能力
# 负责配置校验、端口检测、配置合并和 Web 控制台相关能力

_resources_dir() {
    echo "${CLASH_BASE_DIR}/resources"
}

_config_base_path() {
    echo "$(_resources_dir)/config.yaml"
}

_config_mixin_path() {
    echo "$(_resources_dir)/mixin.yaml"
}

_config_runtime_path() {
    echo "$(_resources_dir)/runtime.yaml"
}

_config_tun_runtime_path() {
    echo "$(_resources_dir)/runtime.tun.yaml"
}

_config_temp_path() {
    echo "$(_resources_dir)/temp.yaml"
}

_bin_dir() {
    echo "${CLASH_BASE_DIR}/bin"
}

_kernel_bin() {
    echo "$(_bin_dir)/${KERNEL_NAME}"
}

_yq_bin() {
    echo "$(_bin_dir)/yq"
}

_subconverter_dir() {
    echo "$(_bin_dir)/subconverter"
}

_subconverter_bin() {
    echo "$(_subconverter_dir)/subconverter"
}

_subconverter_config_path() {
    echo "$(_subconverter_dir)/pref.yml"
}

_subconverter_log_path() {
    echo "$(_subconverter_dir)/latest.log"
}

_profiles_dir() {
    echo "$(_resources_dir)/profiles"
}

_profiles_meta_path() {
    echo "$(_resources_dir)/profiles.yaml"
}

_profiles_log_path() {
    echo "$(_resources_dir)/profiles.log"
}

_get_bind_addr() {
    local allow_lan bind_addr
    bind_addr=$("$(_yq_bin)" '.bind-address // "*"' "$(_config_runtime_path)")
    allow_lan=$("$(_yq_bin)" '.allow-lan // false' "$(_config_runtime_path)")

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
    ext_addr=$("$(_yq_bin)" '.external-controller // ""' "$(_config_runtime_path)")
    local ext_ip=${ext_addr%%:*}
    EXT_IP=$ext_ip
    EXT_PORT=${ext_addr##*:}
    [ "$ext_ip" = '0.0.0.0' ] && EXT_IP=$(_get_local_ip)
    _is_port_used "$EXT_PORT" && {
        curl -s --noproxy "*" -H "Authorization: Bearer $(_get_secret)" "127.0.0.1:${EXT_PORT}" | grep -qs "${KERNEL_NAME}" && return 0
        local new_port=$(_get_random_port)
        _failcat '🎯' "端口冲突：[external-controller] ${EXT_PORT} 🎲 随机分配 $new_port"
        EXT_PORT=$new_port
        "$(_yq_bin)" -i ".external-controller = \"$ext_ip:$new_port\"" "$(_config_mixin_path)"
        _merge_config
    }
}

_valid_config() {
    local config=$1
    [[ ! -e "$config" || "$(wc -l <"$config")" -lt 1 ]] && return 1

    local test_cmd test_log
    test_cmd=("$(_kernel_bin)" -d "$(dirname "$config")" -f "$config" -t)
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
    mixed_port=$("$(_yq_bin)" '.mixed-port // ""' "$(_config_runtime_path)")
    http_port=$("$(_yq_bin)" '.port // ""' "$(_config_runtime_path)")
    socks_port=$("$(_yq_bin)" '.socks-port // ""' "$(_config_runtime_path)")
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
            "$(_yq_bin)" -i ".${yaml_key} = $new_port" "$(_config_mixin_path)"
        }
    done
    ((count)) && _merge_config
}

_merge_config() {
    local config_runtime
    local config_temp
    local config_base
    local config_mixin
    config_runtime=$(_config_runtime_path)
    config_temp=$(_config_temp_path)
    config_base=$(_config_base_path)
    config_mixin=$(_config_mixin_path)
    cat "$config_runtime" >"$config_temp" 2>/dev/null
    # shellcheck disable=SC2016
    "$(_yq_bin)" eval-all '
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
    ' "$config_base" "$config_mixin" >"$config_runtime"
    _valid_config "$config_runtime" || {
        cat "$config_temp" >"$config_runtime"
        _error_quit "验证失败：请检查 Mixin 配置"
    }
}

_get_secret() {
    "$(_yq_bin)" '.secret // ""' "$(_config_runtime_path)"
}
