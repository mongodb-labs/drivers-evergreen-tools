from pymongo import MongoClient
import os
from urllib.request import urlopen, Request
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

audience = os.environ['GCPOIDC_AUDIENCE']
atlas_uri = os.environ["MONGODB_URI"]

class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        url = "http://metadata/computeMetadata/v1/instance/service-accounts/default/identity"
        url += f"?audience={audience}"
        headers = { "Metadata-Flavor": "Google" }
        print('Fetching url', url)
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=context.timeout_seconds) as response:
                status = response.status
                body = response.read().decode('utf8')
        except Exception as e:
            msg = "Failed to acquire IMDS access token: %s" % e
            raise ValueError(msg) from e

        if status != 200:
            print(body)
            msg = "Failed to acquire IMDS access token."
            raise ValueError(msg)

        return OIDCCallbackResult(access_token=body)

props = dict(OIDC_CALLBACK=MyCallback())
print('Testing MONGODB-OIDC on gcp...')
c = MongoClient(f'{atlas_uri}/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
c.test.test.insert_one({})
c.close()
print('Testing MONGODB-OIDC on gcp... done.')
print('Self test complete!')
