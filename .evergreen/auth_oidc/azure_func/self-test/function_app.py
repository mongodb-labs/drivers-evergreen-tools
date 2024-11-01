import json
import logging
import os
from urllib.request import Request, urlopen

import azure.functions as func
from pymongo import MongoClient
from pymongo.auth_oidc import OIDCCallback, OIDCCallbackContext, OIDCCallbackResult

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

def _get_token():
    resource=os.environ['APPSETTING_RESOURCE']
    client_id= os.environ['APPSETTING_CLIENT_ID']
    url = os.environ['IDENTITY_ENDPOINT']
    url += '?api-version=2019-08-01'
    url += f'&resource={resource}'
    url += f'&client_id={client_id}'

    headers = { "X-IDENTITY-HEADER": os.environ['IDENTITY_HEADER'] }

    request = Request(url, headers=headers)
    logging.info('Making a token request.')
    with urlopen(request, timeout=30) as response:
        body = response.read().decode('utf8')
    return json.loads(body)['access_token']


class MyCallback(OIDCCallback):
    def fetch(self, context: OIDCCallbackContext) -> OIDCCallbackResult:
        return OIDCCallbackResult(access_token=_get_token())


@app.route(route="gettoken")
def gettoken(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Handling a gettoken request.')
    try:
        token = _get_token()
    except Exception as e:
        return func.HttpResponse(str(e), status_code=500)
    logging.info('Returning the token.')
    return func.HttpResponse(token)


@app.route(route='oidcselftest')
def oidcselftest(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Handling an oidcselftest request.')
    try:
        req_body = req.get_json()
        uri = req_body.get('MONGODB_URI')
        props = dict(OIDC_CALLBACK=MyCallback())
        logging.info('Testing MONGODB-OIDC on azure functions...')
        c = MongoClient(f'{uri}/?authMechanism=MONGODB-OIDC', authMechanismProperties=props)
        c.test.test.insert_one({})
        c.close()
    except Exception as e:
        return func.HttpResponse(str(e), status_code=500)
    logging.info('Testing MONGODB-OIDC on azure functions... done.')
    logging.info('Self test complete!')
    return func.HttpResponse('Success!')
