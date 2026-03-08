#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnused common-updater-scripts jq prefetch-npm-deps unzip nix-prefetch
set -euo pipefail

root="$(dirname "$(readlink -f "$0")")"
repo_root="$(git -C "$root" rev-parse --show-toplevel)"
cd "$repo_root"

version=$(curl ${GITHUB_TOKEN:+" -u \":$GITHUB_TOKEN\""} -s https://api.github.com/repos/microsoft/playwright-python/releases/latest | jq -r '.tag_name | sub("^v"; "")')
# Most of the time, this should be the latest stable release of the Node-based
# Playwright version, but that isn't a guarantee, so this needs to be specified
# as well:
setup_py_url="https://github.com/microsoft/playwright-python/raw/v${version}/setup.py"
driver_version_setup_py=$(curl -Ls "$setup_py_url" | grep '^driver_version =' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
python_major_minor=$(echo "$version" | sed -E 's/^([0-9]+\.[0-9]+)\..*$/\1/')
resolve_driver_version_latest_patch() {
    local mm_escaped
    mm_escaped=$(echo "$python_major_minor" | sed 's/\./\\./g')
    curl -fsSL "https://registry.npmjs.org/playwright" \
        | jq -r '.versions | keys[]' \
        | grep -E "^${mm_escaped}\.[0-9]+$" \
        | sort -V \
        | tail -n1
}
driver_version="$(resolve_driver_version_latest_patch || true)"
if [ -z "${driver_version}" ]; then
    driver_version="$driver_version_setup_py"
fi

# TODO: skip if update-source-version reported the same version
update-source-version playwright-driver "$driver_version"
update-source-version python3Packages.playwright "$version"

driver_file="$root/driver.nix"
repo_url_prefix="https://raw.githubusercontent.com/microsoft/playwright"

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

# Update playwright-mcp package
driver_major_minor=$(echo "$driver_version" | sed -E 's/^([0-9]+\.[0-9]+)\..*$/\1/')
resolve_mcp_version() {
    local releases_json
    releases_json=$(curl ${GITHUB_TOKEN:+" -u \":$GITHUB_TOKEN\""} -s "https://api.github.com/repos/microsoft/playwright-mcp/releases?per_page=100")
    while IFS= read -r tag_name; do
        local mcp_version_candidate mcp_npm_url mcp_playwright_dep mcp_major_minor
        mcp_version_candidate=$(echo "$tag_name" | sed 's/^v//')
        mcp_npm_url="https://registry.npmjs.org/@playwright/mcp/${mcp_version_candidate}"
        mcp_playwright_dep=$(
            curl -fsSL "$mcp_npm_url" \
                | jq -r '.dependencies.playwright // .dependencies["playwright-core"] // empty'
        ) || continue
        mcp_major_minor=$(echo "$mcp_playwright_dep" | grep -Eo '[0-9]+\.[0-9]+' | head -n1 || true)
        if [ "$mcp_major_minor" = "$driver_major_minor" ]; then
            echo "$mcp_version_candidate"
            return 0
        fi
    done < <(echo "$releases_json" | jq -r '.[].tag_name')
    return 1
}
mcp_version="$(resolve_mcp_version)" || {
    echo "Could not find a playwright-mcp release compatible with Playwright driver ${driver_version}" >&2
    exit 1
}
update-source-version playwright-mcp "$mcp_version"

# Update npmDepsHash for playwright-mcp
pushd "$temp_dir" >/dev/null
curl -fsSL -o package-lock.json "https://raw.githubusercontent.com/microsoft/playwright-mcp/v${mcp_version}/package-lock.json"
mcp_npm_hash=$(prefetch-npm-deps package-lock.json)
rm -f package-lock.json
popd >/dev/null

mcp_package_file="$root/../../../by-name/pl/playwright-mcp/package.nix"
sed -E 's#\bnpmDepsHash = ".*?"#npmDepsHash = "'"$mcp_npm_hash"'"#' -i "$mcp_package_file"


# update binaries of browsers, used by playwright.
replace_sha() {
  sed -i "s|$2 = \".\{44,52\}\"|$2 = \"$3\"|" "$1"
}

prefetch_browser() {
  # nix-prefetch is used to obtain sha with `stripRoot = false`
  # doesn't work on macOS https://github.com/msteen/nix-prefetch/issues/53
  nix-prefetch --option extra-experimental-features flakes -q "{ stdenv, fetchzip }: stdenv.mkDerivation { name=\"browser\"; src = fetchzip { url = \"$1\"; stripRoot = $2; }; }"
}

browser_download_url() {
    local name="$1"
    local buildname="$2"
    local platform="$3"
    local arch="$4"
    local revision="$5"
    local browser_version="$6"
    local suffix="$7"

    # Chromium and chromium-headless-shell use Chrome for Testing artifacts on
    # Linux/macOS on x86_64 and aarch64-darwin.
    if [ "$name" = "chromium" ] || [ "$name" = "chromium-headless-shell" ]; then
        if [ "$name" = "chromium" ]; then
            artifact="chrome"
        else
            artifact="chrome-headless-shell"
        fi

        if [ "$platform" = "linux" ] && [ "$arch" = "x86_64" ]; then
            echo "https://cdn.playwright.dev/chrome-for-testing-public/${browser_version}/linux64/${artifact}-linux64.zip"
            return
        fi

        if [ "$platform" = "darwin" ]; then
            if [ "$arch" = "x86_64" ]; then
                cft_platform="mac-x64"
            else
                cft_platform="mac-arm64"
            fi
            echo "https://cdn.playwright.dev/chrome-for-testing-public/${browser_version}/${cft_platform}/${artifact}-${cft_platform}.zip"
            return
        fi
    fi

    echo "https://cdn.playwright.dev/dbazure/download/playwright/builds/${buildname}/${revision}/${name}-${suffix}.zip"
}

update_browser() {
    name="$1"
    platform="$2"
    stripRoot="false"
    if [ "$platform" = "darwin" ]; then
        if [ "$name" = "webkit" ]; then
            suffix="mac-14"
        else
            suffix="mac"
        fi
    else
        if [ "$name" = "ffmpeg" ] || [ "$name" = "chromium-headless-shell" ]; then
            suffix="linux"
        elif [ "$name" = "chromium" ]; then
            stripRoot="true"
            suffix="linux"
        elif [ "$name" = "firefox" ]; then
            stripRoot="true"
            suffix="ubuntu-22.04"
        else
            suffix="ubuntu-22.04"
        fi
    fi
    aarch64_suffix="$suffix-arm64"
    if [ "$name" = "chromium-headless-shell" ]; then
        buildname="chromium";
    else
        buildname="$name"
    fi

    revision="$(jq -r ".browsers[\"$buildname\"].revision" "$root/browsers.json")"
    browser_version="$(jq -r ".browsers[\"$buildname\"].browserVersion // empty" "$root/browsers.json")"
    x86_64_url="$(browser_download_url "$name" "$buildname" "$platform" "x86_64" "$revision" "$browser_version" "$suffix")"
    aarch64_url="$(browser_download_url "$name" "$buildname" "$platform" "aarch64" "$revision" "$browser_version" "$aarch64_suffix")"
    replace_sha "$root/$name.nix" "x86_64-$platform" \
        "$(prefetch_browser "$x86_64_url" "$stripRoot")"
    replace_sha "$root/$name.nix" "aarch64-$platform" \
        "$(prefetch_browser "$aarch64_url" "$stripRoot")"
}

curl -fsSl \
    "https://raw.githubusercontent.com/microsoft/playwright/v${driver_version}/packages/playwright-core/browsers.json" \
    | jq '
      .comment = "This file is kept up to date via update.sh"
      | .browsers |= (
        [.[]
          | select(.installByDefault) | del(.installByDefault)]
          | map({(.name): . | del(.name)})
          | add
      )
    ' > "$root/browsers.json"

update_browser "chromium" "linux"
update_browser "chromium-headless-shell" "linux"
update_browser "firefox" "linux"
update_browser "webkit" "linux"
update_browser "ffmpeg" "linux"

update_browser "chromium" "darwin"
update_browser "chromium-headless-shell" "darwin"
update_browser "firefox" "darwin"
update_browser "webkit" "darwin"
update_browser "ffmpeg" "darwin"

# Update package-lock.json files for all npm deps that are built in playwright

# Function to download `package-lock.json` for a given source path and update hash
update_hash() {
    local source_root_path="$1"
    local existing_hash="$2"

    # Formulate download URL
    local download_url="${repo_url_prefix}/v${driver_version}${source_root_path}/package-lock.json"
    # Download package-lock.json to temporary directory
    curl -fsSL -o "${temp_dir}/package-lock.json" "$download_url"

    # Calculate the new hash
    local new_hash
    new_hash=$(prefetch-npm-deps "${temp_dir}/package-lock.json")

    # Update npmDepsHash in the original file
    sed -i "s|$existing_hash|${new_hash}|" "$driver_file"
}

while IFS= read -r source_root_line; do
    [[ "$source_root_line" =~ sourceRoot ]] || continue
    source_root_path=$(echo "$source_root_line" | sed -e 's/^.*"${src.name}\(.*\)";.*$/\1/')
    # Extract the current npmDepsHash for this sourceRoot
    existing_hash=$(grep -A1 "$source_root_line" "$driver_file" | grep 'npmDepsHash' | sed -e 's/^.*npmDepsHash = "\(.*\)";$/\1/')

    # Call the function to download and update the hash
    update_hash "$source_root_path" "$existing_hash"
done < "$driver_file"
