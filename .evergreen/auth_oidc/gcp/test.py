from pymongo import MongoClient
import os
import json
from urllib.request import urlopen, Request
from pymongo.auth import _AUTH_MAP, _authenticate_oidc
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

# Force MONGODB-OIDC to be enabled.
_AUTH_MAP["MONGODB-OIDC"] = _authenticate_oidc

audience = os.environ['GCPOIDC_AUDIENCE']

class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        url = "'http://metadata/computeMetadata/v1/instance/service-accounts/default/identity"
        url += f"&audience={audience}"
        headers = { "Metadata-Flavor": "Google", "Accept": "application/json" }
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
            raise ValueError("GCP IMDS response must be in JSON format.")

        for key in ["access_token", "expires_in"]:
            if not data.get(key):
                msg = "GCP IMDS response must contain %s, but was %s."
                msg = msg % (key, body)
                raise ValueError(msg)
        return OIDCCallbackResult(access_token=data['access_token'])

props = dict(OIDC_CALLBACK=MyCallback())
print('Testing MONGODB-OIDC on gcp...')
c = MongoClient('mongodb://localhost:27017/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
c.test.test.insert_one({})
c.close()
print('Testing MONGODB-OIDC on gcp... done.')
print('Self test complete!')
