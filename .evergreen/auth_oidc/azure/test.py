from pymongo import MongoClient
import os
import json
from urllib.request import urlopen, Request
from pymongo.auth import _AUTH_MAP, _authenticate_oidc

# Force MONGODB-OIDC to be enabled.
_AUTH_MAP["MONGODB-OIDC"] = _authenticate_oidc

app_id = os.environ['AZUREOIDC_CLIENTID']

def callback(client_info, server_info):
    url = "http://169.254.169.254/metadata/identity/oauth2/token"
    url += "?api-version=2018-02-01"
    url += f"&resource=api://{app_id}"
    headers = { "Metadata": "true", "Accept": "application/json" }
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=server_info['timeout_seconds']) as response:
            status = response.status
            body = response.read().decode('utf8')
    except Exception as e:
        msg = "Failed to acquire IMDS access token: %s" % e
        raise ValueError(msg)

    if status != 200:
        print(body)
        msg = "Failed to acquire IMDS access token."
        raise ValueError(msg)
    try:
        data = json.loads(body)
    except Exception:
        raise ValueError("Azure IMDS response must be in JSON format.")

    for key in ["access_token", "expires_in"]:
        if not data.get(key):
            msg = "Azure IMDS response must contain %s, but was %s."
            msg = msg % (key, body)
            raise ValueError(msg)
    return dict(access_token=data['access_token'])


props = dict(request_token_callback=callback)
print('Testing MONGODB-OIDC on azure')
c = MongoClient('mongodb://localhost:27017/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
c.test.test.find_one({})
c.close()
print('Self test complete!')