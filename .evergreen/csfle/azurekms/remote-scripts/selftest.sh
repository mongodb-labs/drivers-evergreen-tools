echo "This is a self-test intended to run on an Azure Virtual Machine."

echo "Get token with resource=https://management.azure.com ... begin"
REPLY=$(curl -s "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" -H "Metadata: true")
ACCESS_TOKEN=$(echo $REPLY | jq .access_token -r)
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Unexpected empty access token. The Virtual Machine may not have an assigned managed-identity. Reply from IMDS: $REPLY"
    exit 1
fi
echo "Got expected access token"
echo "Get token with resource=https://management.azure.com ... end"

echo "Get token with resource=https://vault.azure.com/ ... begin"
REPLY=$(curl -s "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" -H "Metadata: true")
ACCESS_TOKEN=$(echo $REPLY | jq .access_token -r)
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Unexpected empty access token. The Virtual Machine may not have access to the key vault. Reply from IMDS: $REPLY"
    exit 1
fi
echo "Got expected access token"
echo "Get token with resource=https://vault.azure.com/ ... end"

echo "Encrypt with key ... begin"
REPLY=$(curl -s -X POST https://keyvault-drivers-2411.vault.azure.net/keys/KEY-NAME/b11dc726b8d24a79a670e27619ff22c8/encrypt?api-version=7.3 \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{ "alg": "RSA1_5", "value": "5ka5IVsnGrzufA" }' \
    )
VALUE=$(echo $REPLY | jq .value -r)
if [ -z "$VALUE" ]; then
    echo "Unexpected empty value. This Virtual Machine may not be authorized to access the key. Reply from key vault API: $REPLY"
    exit 1
fi
echo "Encrypt with key ... end"
