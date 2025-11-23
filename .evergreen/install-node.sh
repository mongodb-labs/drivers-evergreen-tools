#!/usr/bin/env bash
set -o errexit  # Exit the script with error if any of the commands fail

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

DEFAULT_NODE_VERSION=20
if grep -q "release 7" /etc/redhat-release 2> /dev/null; then
  DEFAULT_NODE_VERSION=16
fi
NODE_LTS_VERSION=${NODE_LTS_VERSION:-$DEFAULT_NODE_VERSION}

# If NODE_LTS_VERSION is numeric and less than 18, default to 9, if less than 20, default to 10.
# Do not override if it is already set.
if [[ "$NODE_LTS_VERSION" =~ ^[0-9]+$ && "$NODE_LTS_VERSION" -lt 18 ]]; then
  NPM_VERSION=${NPM_VERSION:-9}
elif [[ "$NODE_LTS_VERSION" =~ ^[0-9]+$ && "$NODE_LTS_VERSION" -lt 20 ]]; then
  NPM_VERSION=${NPM_VERSION:-10}
else
  NPM_VERSION=${NPM_VERSION:-latest}
fi
export NPM_VERSION=${NPM_VERSION}

source "$SCRIPT_DIR/init-node-and-npm-env.sh"

if [[ -z "${npm_global_prefix}" ]]; then echo "npm_global_prefix is unset" && exit 1; fi
if [[ -z "${NODE_ARTIFACTS_PATH}" ]]; then echo "NODE_ARTIFACTS_PATH is unset" && exit 1; fi

function debug_output {
  echo "node location: $(which node)"
  echo "node version: $(node -v)"
  echo "npm location: $(which npm)"
  echo "npm version: $(npm -v)"
}

# Bail early if this version of node was already installed.
if grep -Fxq "$NODE_LTS_VERSION" $NODE_ARTIFACTS_PATH/node-version.txt 2> /dev/null; then
  echo "Node $NODE_LTS_VERSION already installed!"
  debug_output
  exit 0
fi

# Ensure a clean directory.
rm -rf $NODE_ARTIFACTS_PATH
mkdir -p "$NODE_ARTIFACTS_PATH/npm_global"

echo "Installing Node.js $NODE_LTS_VERSION..."

CURL_FLAGS=(
  --fail          # Exit code 1 if request fails
  --compressed    # Request a compressed response should keep fetching fast
  --location      # Follow a redirect
  --retry 8       # Retry HTTP 408, 429, 500, 502, 503 or 504, 8 times
  --silent        # Do not print a progress bar
  --show-error    # Despite the silent flag still print out errors
  --max-time 900  # 900 seconds is 15 minutes, evergreen times out at 20
)

# Comparisons are all case insensitive
shopt -s nocasematch

# index.tab is a sorted tab separated values file with the following headers
# 0       1    2     3   4  5  6    7       8       9   10
# version date files npm v8 uv zlib openssl modules lts security
"$SCRIPT_DIR/retry-with-backoff.sh" curl "${CURL_FLAGS[@]}" "https://nodejs.org/dist/index.tab" --output node_index.tab > /dev/null 2>&1

while IFS=$'\t' read -r -a row; do
  node_index_version="${row[0]}"
  node_index_major_version=$(echo $node_index_version | sed -E 's/^v([0-9]+).*$/\1/')
  node_index_date="${row[1]}"
  [[ "$node_index_version" = "version" ]] && continue # skip tsv header
  [[ "$NODE_LTS_VERSION" = "latest" ]] && break # first line is latest
  [[ "$NODE_LTS_VERSION" = "$node_index_version" ]] && break # match full version if specified (v<major>.<minor>.<patch>)
  [[ "v$NODE_LTS_VERSION" = "$node_index_version" ]] && break # match full version if specified (without leading `v`)
  [[ "$NODE_LTS_VERSION" = "$node_index_major_version" ]] && break # case insensitive compare
done < node_index.tab

if [[ "${OS:-}" = "Windows_NT" ]]; then
  operating_system="win"
elif [[ $(uname) = "darwin" ]]; then
  operating_system="darwin"
elif [[ $(uname) = "linux" ]]; then
  operating_system="linux"
else
  echo "Unable to determine operating system: $operating_system"
  exit 1
fi

architecture=$(uname -m)
if [[ $architecture = "x86_64" ]]; then
  architecture="x64"
elif [[ $architecture = "arm64" ]]; then
  architecture="arm64"
elif [[ $architecture = "aarch64" ]]; then
  architecture="arm64"
elif [[ $architecture == s390* ]]; then
  architecture="s390x"
elif [[ $architecture == ppc* ]]; then
  architecture="ppc64le"
else
  echo "Unable to determine operating system: $architecture"
  exit 1
fi

file_extension="tar.gz"
if [[ "${OS:-}" = "Windows_NT" ]]; then file_extension="zip"; fi

node_directory="node-${node_index_version}-${operating_system}-${architecture}"
node_archive="${node_directory}.${file_extension}"
node_archive_path="$NODE_ARTIFACTS_PATH/${node_archive}"
node_shasum_path="$NODE_ARTIFACTS_PATH/SHASUMS256.txt"
node_download_url="https://nodejs.org/dist/${node_index_version}/${node_archive}"
node_shasum_url="https://nodejs.org/dist/${node_index_version}/SHASUMS256.txt"

echo "Node.js ${node_index_version} for ${operating_system}-${architecture} released on ${node_index_date}"

"$SCRIPT_DIR/retry-with-backoff.sh" curl "${CURL_FLAGS[@]}" "${node_download_url}" --output "$node_archive_path" > /dev/null 2>&1
"$SCRIPT_DIR/retry-with-backoff.sh" curl "${CURL_FLAGS[@]}" "${node_shasum_url}" --output "$node_shasum_path" > /dev/null 2>&1

# Remove extra entries from the SHASUMS256.txt file. Not every OS supports the --ignore-missing flag.
(
  cd "$NODE_ARTIFACTS_PATH"
  awk '{ if (system("[ -e \"" $2 "\" ]") == 0) print $0 }' SHASUMS256.txt > SHASUMS256.filtered.txt
  sha256sum -c SHASUMS256.filtered.txt > /dev/null 2>&1 || sha256sum -c SHASUMS256.filtered.txt
)

if [[ "$file_extension" = "zip" ]]; then
    unzip -q "$node_archive_path" -d "${NODE_ARTIFACTS_PATH}"
    mkdir -p "${NODE_ARTIFACTS_PATH}/nodejs"
    # Windows "bins" are at the top level
    mv "${NODE_ARTIFACTS_PATH}/${node_directory}" "${NODE_ARTIFACTS_PATH}/nodejs/bin"
    # Need to add executable flag ourselves
    chmod +x "${NODE_ARTIFACTS_PATH}/nodejs/bin/node.exe"
    chmod +x "${NODE_ARTIFACTS_PATH}/nodejs/bin/npm"
else
    tar -xf "$node_archive_path" -C "${NODE_ARTIFACTS_PATH}"
    mv "${NODE_ARTIFACTS_PATH}/${node_directory}" "${NODE_ARTIFACTS_PATH}/nodejs"
fi
echo "$NODE_LTS_VERSION" > $NODE_ARTIFACTS_PATH/node-version.txt
echo "Installing Node.js $NODE_LTS_VERSION... done."

if [[ $operating_system != "win" ]]; then
  # Update npm to latest when we can
  echo "Installing npm $NPM_VERSION..."
  npm install --silent --global npm@$NPM_VERSION
  hash -r
  echo "Installing npm $NPM_VERSION... done."
fi

debug_output
