#!/usr/bin/env bash
# Get an installation access token.
# Adapted from
# https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#example-using-bash-to-generate-a-jwt
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR > /dev/null

source ./secrets-export.sh

client_id="$GITHUB_APP_ID"

repo=$1
org=${2:-mongodb}

pem=$(echo "$GITHUB_SECRET_KEY" | sed 's/\\n/\n/g')

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json='{
    "iat":'"${iat}"',
    "exp":'"${exp}"',
    "iss":'"${client_id}"'
}'
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT.
JWT="${header_payload}"."${signature}"

# Get an installation access token.
installation_id=$GITHUB_APP_INSTALL_ID_MONGODB
if [ "$org" == "mongodb-labs" ]; then
    installation_id=$GITHUB_APP_INSTALL_ID_MONGODB_LABS
fi
rep=$(curl --silent --request POST \
--url "https://api.github.com/app/installations/$installation_id/access_tokens" \
--header "Accept: application/vnd.github+json" \
--header "Authorization: Bearer $JWT" \
--header "X-GitHub-Api-Version: 2022-11-28" \
-d '{"repositories":["'$repo'"],"permissions":{"pull_requests":"write","contents":"write"}}')
echo $rep | jq -r '.token'

popd > /dev/null
