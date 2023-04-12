from pymongo import MongoClient
import requests
import os

app_id = os.environ['AZUREOIDC_CLIENTID']
client_id = os.environ['AZUREOIDC_TOKENCLIENT']

def callback(client_info, server_info):
    url = "http://169.254.169.254/metadata/identity/oauth2/token"
    url += "?api-version=2018-02-01"
    url += f"&resource=api://{app_id}"
    url += f"&client_id={client_id}"
    headers = { "Metadata": "true", "Accept": "application/json" }
    try:
        response = requests.get(url, headers=headers)
    except Exception as e:
        msg = "Failed to acquire IMDS access token: %s" % e
        raise ValueError(msg)

    if response.status_code != 200:
        print(response.text)
        msg = "Failed to acquire IMDS access token."
        raise ValueError(msg)
    try:
        data = response.json()
    except Exception:
        raise ValueError("Azure IMDS response must be in JSON format.")

    for key in ["access_token", "expires_in"]:
        if not data.get(key):
            msg = "Azure IMDS response must contain %s, but was %s."
            msg = msg % (key, response.content)
            raise ValueError(msg)
    return dict(access_token=data['access_token'])


props = dict(request_token_callback=callback)
print('Testing MONGODB-OIDC on azure')
c = MongoClient('mongodb://localhost:27017/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
c.test.test.find_one({})
c.close()
print('Great success!')