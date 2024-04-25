from pymongo import MongoClient
import os
import json
from urllib.request import urlopen, Request
from pymongo.auth import _AUTH_MAP, _authenticate_oidc
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

# Force MONGODB-OIDC to be enabled.
_AUTH_MAP["MONGODB-OIDC"] = _authenticate_oidc

app_id = os.environ['AZUREOIDC_APP_ID']
client_id = os.environ['AZUREOIDC_USERNAME']

class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        url = "http://169.254.169.254/metadata/identity/oauth2/token"
        url += "?api-version=2018-02-01"
        url += f"&resource=api://{app_id}"
        url += f"&client_id={client_id}"
        headers = { "Metadata": "true", "Accept": "application/json" }
        print('Fetching url', url)
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=context.timeout_seconds) as response:
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
        return OIDCCallbackResult(access_token=data['access_token'])

props = dict(OIDC_CALLBACK=MyCallback())
print('Testing MONGODB-OIDC on azure...')
c = MongoClient('mongodb://localhost:27017/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
c.test.test.insert_one({})
c.close()
print('Testing MONGODB-OIDC on azure... done.')
print('Self test complete!')
