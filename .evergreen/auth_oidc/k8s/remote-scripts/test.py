import os

from pymongo import MongoClient
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

atlas_uri = os.environ["MONGODB_URI"]


class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        fname = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        for key in ["AZURE_FEDERATED_TOKEN_FILE", "AWS_WEB_IDENTITY_TOKEN_FILE"]:
            if key in os.environ:
                fname = os.environ[key]
        with open(fname) as fid:
            token = fid.read()
        return OIDCCallbackResult(access_token=token)


props = dict(OIDC_CALLBACK=MyCallback())
print("Testing MONGODB-OIDC on k8s...")
c = MongoClient(
    f"{atlas_uri}/?authMechanism=MONGODB-OIDC", authMechanismProperties=props
)
c.test.test.insert_one({})
c.close()
print("Testing MONGODB-OIDC on k8s... done.")
print("Self test complete!")
