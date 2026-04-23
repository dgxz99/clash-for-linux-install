#!/usr/bin/env bash

# 安装资源能力
# 负责下载、校验并释放内核与前端依赖

# 根据所选内核准备需要的压缩包并解压到安装目录
_prepare_zip() {
    _init_temp_dir
    trap '_cleanup_temp_dir' EXIT
    local required_zips=("mihomo" "yq" "subconverter" "ui")

    _download_zip "${required_zips[@]}"

    ZIP_KERNEL="$ZIP_MIHOMO"
    BIN_KERNEL="${BIN_BASE_DIR}/$KERNEL_NAME"
    _unzip_zip
    _cleanup_temp_dir
    trap - EXIT
}

# 初始化安装过程使用的临时目录
_init_temp_dir() {
    TEMP_ROOT_DIR="$(pwd)/tmp"
    mkdir -p "$TEMP_ROOT_DIR" || _error_quit "无法创建安装临时根目录：$TEMP_ROOT_DIR"
    TEMP_BASE_DIR=$(mktemp -d "${TEMP_ROOT_DIR}/${KERNEL_NAME}-install.XXXXXX") ||
        _error_quit "无法创建安装临时目录"
    TEMP_DOWNLOAD_DIR="${TEMP_BASE_DIR}/download"
    TEMP_EXTRACT_DIR="${TEMP_BASE_DIR}/extract"
    mkdir -p "$TEMP_DOWNLOAD_DIR" "$TEMP_EXTRACT_DIR"
}

# 清理安装过程中的临时目录
_cleanup_temp_dir() {
    [ -n "${TEMP_BASE_DIR:-}" ] && [ -d "$TEMP_BASE_DIR" ] && rm -rf "$TEMP_BASE_DIR"
    [ -n "${TEMP_ROOT_DIR:-}" ] && [ -d "$TEMP_ROOT_DIR" ] && rmdir "$TEMP_ROOT_DIR" 2>/dev/null || true
    TEMP_ROOT_DIR=
    TEMP_BASE_DIR=
    TEMP_DOWNLOAD_DIR=
    TEMP_EXTRACT_DIR=
}

# 获取 x86_64 平台对应的 mihomo 优化等级
_get_x86_64_optimization_level() {
    local flags
    flags=$(grep -m1 '^flags' /proc/cpuinfo)
    local level=v1
    grep -qw sse4_2 <<<"$flags" && grep -qw popcnt <<<"$flags" && level=v2
    grep -qw avx2 <<<"$flags" && grep -qw fma <<<"$flags" && level=v3
    echo "$level"
}

# 通过 GitHub releases/latest 跳转解析仓库最新 tag
_resolve_latest_release_tag() {
    local repo=$1
    local name=${2:-$repo}
    local fallback_version=${3:-}
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local request_url="${URL_GH_API_PROXY:+${URL_GH_API_PROXY%/}/}${api_url}"
    local response
    local latest_tag

    _okcat '⏳' "正在获取 ${name} 最新版本信息..." >&2

    response=$(
        curl \
            --silent \
            --show-error \
            --fail \
            --insecure \
            --location \
            --retry 1 \
            -H 'Accept: application/vnd.github+json' \
            "$request_url"
    ) || {
        [ -n "$fallback_version" ] && {
            _failcat '⚠️ ' "获取 ${name} 最新版本失败，回退到默认版本：$fallback_version"
            echo "$fallback_version"
            return 0
        }
        _error_quit "无法获取 ${name} 最新版本，请检查网络或 API 代理"
    }

    latest_tag=$(
        printf '%s\n' "$response" |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1
    )

    [[ "$latest_tag" =~ ^v[0-9] ]] || {
        [ -n "$fallback_version" ] && {
            _failcat '⚠️ ' "解析 ${name} 最新版本失败，回退到默认版本：$fallback_version"
            echo "$fallback_version"
            return 0
        }
        _error_quit "无法解析 ${name} 最新版本"
    }

    _okcat '✅' "获取到 ${name} 最新版本：$latest_tag" >&2
    echo "$latest_tag"
}

# 根据 release 资产名称构建 GitHub 下载地址
_build_github_release_download_url() {
    local repo=$1
    local version=$2
    local asset_name=$3
    echo "https://github.com/${repo}/releases/download/${version}/${asset_name}"
}

# 根据架构构建 mihomo 下载地址
_build_mihomo_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        local level=$(_get_x86_64_optimization_level)
        asset_name="mihomo-linux-amd64-${level}-${version}.gz"
        ;;
    *86*)
        asset_name="mihomo-linux-386-${version}.gz"
        ;;
    armv*)
        asset_name="mihomo-linux-armv7-${version}.gz"
        ;;
    aarch64)
        asset_name="mihomo-linux-arm64-${version}.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "MetaCubeX/mihomo" "$version" "$asset_name"
}

# 根据架构构建 yq 下载地址
_build_yq_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        asset_name="yq_linux_amd64.tar.gz"
        ;;
    *86*)
        asset_name="yq_linux_386.tar.gz"
        ;;
    armv*)
        asset_name="yq_linux_arm.tar.gz"
        ;;
    aarch64)
        asset_name="yq_linux_arm64.tar.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "mikefarah/yq" "$version" "$asset_name"
}

# 根据架构构建 subconverter 下载地址
_build_subconverter_download_url() {
    local arch=$1
    local version=$2
    local asset_name
    case "$arch" in
    x86_64)
        asset_name="subconverter_linux64.tar.gz"
        ;;
    *86*)
        asset_name="subconverter_linux32.tar.gz"
        ;;
    armv*)
        asset_name="subconverter_armv7.tar.gz"
        ;;
    aarch64)
        asset_name="subconverter_aarch64.tar.gz"
        ;;
    *)
        return 1
        ;;
    esac

    _build_github_release_download_url "tindy2013/subconverter" "$version" "$asset_name"
}

# 构建 zashboard 下载地址
_build_ui_download_url() {
    local version=$1
    _build_github_release_download_url "Zephyruso/zashboard" "$version" "dist.zip"
}

# 按 CPU 架构下载所需二进制资源
_download_zip() {
    (($#)) || return 0
    local url_mihomo url_yq url_subconverter url_ui
    local arch
    arch=$(uname -m)
    local level=''
    VERSION_MIHOMO=$(_resolve_latest_release_tag "MetaCubeX/mihomo" "mihomo" "${VERSION_MIHOMO:-}")
    VERSION_YQ=$(_resolve_latest_release_tag "mikefarah/yq" "yq" "${VERSION_YQ:-}")
    VERSION_SUBCONVERTER=$(_resolve_latest_release_tag "tindy2013/subconverter" "subconverter" "${VERSION_SUBCONVERTER:-}")
    VERSION_UI=$(_resolve_latest_release_tag "Zephyruso/zashboard" "zashboard" "${VERSION_UI:-}")
    url_ui=$(_build_ui_download_url "$VERSION_UI")
    case "$arch" in
    x86_64)
        level=$(_get_x86_64_optimization_level)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    *86* | armv* | aarch64)
        url_mihomo=$(_build_mihomo_download_url "$arch" "$VERSION_MIHOMO")
        url_yq=$(_build_yq_download_url "$arch" "$VERSION_YQ")
        url_subconverter=$(_build_subconverter_download_url "$arch" "$VERSION_SUBCONVERTER")
        ;;
    *)
        _error_quit "未知的架构版本：$arch，请检查架构支持情况后重试"
        ;;
    esac

    local -A urls=(
        [mihomo]="$url_mihomo"
        [yq]="$url_yq"
        [subconverter]="$url_subconverter"
        [ui]="$url_ui"
    )

    local item target_zips=()
    _okcat '🖥️ ' "系统架构：$arch $level"
    for item in "$@"; do
        local url="${urls[$item]}"
        local proxy_url="${URL_GH_PROXY:+${URL_GH_PROXY%/}/}${url}"
        url="$proxy_url"
        _okcat '⏳' "正在下载：${item}：$url"
        local target="${TEMP_DOWNLOAD_DIR}/$(basename "$url")"
        curl \
            --progress-bar \
            --show-error \
            --fail \
            --insecure \
            --location \
            --retry 1 \
            --output "$target" \
            "$url"
        case "$item" in
        mihomo)
            ZIP_MIHOMO=$target
            ;;
        yq)
            ZIP_YQ=$target
            ;;
        subconverter)
            ZIP_SUBCONVERTER=$target
            ;;
        ui)
            ZIP_UI=$target
            ;;
        esac
        target_zips+=("$target")
    done
    _valid_zip "${target_zips[@]}"
}

# 校验下载到的压缩包是否完整可用
_valid_zip() {
    (($#)) || return 1
    local zip fail_zips=()
    for zip in "$@"; do
        gzip -tq "$zip" || unzip -tqq "$zip" || fail_zips+=("$zip")
    done

    ((${#fail_zips[@]})) && _error_quit "文件验证失败：${fail_zips[*]} 请检查网络后重试"
}

# 将压缩包中的二进制和前端资源释放到目标目录
_unzip_zip() {
    local temp_bin_dir="${TEMP_EXTRACT_DIR}/bin"
    local temp_ui_dir="${TEMP_EXTRACT_DIR}/ui"
    local temp_yq
    _valid_zip "$ZIP_KERNEL" "$ZIP_YQ" "$ZIP_SUBCONVERTER" "$ZIP_UI"
    mkdir -p "$temp_bin_dir" "$temp_ui_dir" "$BIN_BASE_DIR" "$CLASH_RESOURCES_DIR"

    gzip -dc "$ZIP_KERNEL" >"${temp_bin_dir}/${KERNEL_NAME}"
    /usr/bin/install -Dm755 "${temp_bin_dir}/${KERNEL_NAME}" "$BIN_KERNEL"

    tar -xf "$ZIP_YQ" -C "$temp_bin_dir"
    temp_yq=$(echo "${temp_bin_dir}"/yq_*)
    /usr/bin/install -Dm755 "$temp_yq" "$BIN_YQ"

    tar -xf "$ZIP_SUBCONVERTER" -C "$temp_bin_dir"
    mkdir -p "$BIN_SUBCONVERTER_DIR"
    /bin/cp -rf "${temp_bin_dir}/subconverter/." "$BIN_SUBCONVERTER_DIR"
    /bin/cp "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG"

    unzip -oqq "$ZIP_UI" -d "$temp_ui_dir" 2>/dev/null || tar -xf "$ZIP_UI" -C "$temp_ui_dir"
    /bin/cp -rf "${temp_ui_dir}/." "$RESOURCES_BASE_DIR"
}
