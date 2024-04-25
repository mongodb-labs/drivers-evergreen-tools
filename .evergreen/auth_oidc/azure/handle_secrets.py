import logging
import os
from base64 import b64decode

from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential


def main():
    vault_name = os.environ["AZUREOIDC_KEYVAULT"]
    private_key_file = os.environ['AZUREKMS_PRIVATEKEYPATH']
    public_key_file = os.environ['AZUREKMS_PUBLICKEYPATH']
    env_file = os.environ['AZUREOIDC_ENVPATH']
    app_id = os.environ['AZUREOIDC_CLIENTID']
    tenant_id = os.environ['AZUREOIDC_TENANTID']
    vault_uri = f"https://{vault_name}.vault.azure.net"
    print('Getting secrets from vault ... begin')

    logger = logging.getLogger('azure.mgmt.resource')

    # Set the desired logging level
    logger.setLevel(logging.DEBUG)

    credential = DefaultAzureCredential(exclude_environment_credential=True, exclude_managed_identity_credential=True)
    client = SecretClient(vault_url=vault_uri, credential=credential)

    secrets = dict()
    for secret in ['RESOURCEGROUP', 'PUBLICKEY', 'PRIVATEKEY', 'AUTHCLAIM', 'AUTHPREFIX', 'IDENTITY',
                   'USERNAME', 'AUDIENCE']:
        retrieved = client.get_secret(secret)
        secrets[secret] = retrieved.value

    uri = "mongodb://localhost"
    suffix = "authMechanism=MONGODB-OIDC&authMechanismProperties=ENVIRONMENT:azure"
    suffix += f",TOKEN_RESOURCE:{secrets['AUDIENCE']}"
    with open(env_file, 'w') as fid:
        fid.write(f'export AZUREOIDC_RESOURCEGROUP={secrets["RESOURCEGROUP"]}\n')
        fid.write(f'export AZUREKMS_RESOURCEGROUP={secrets["RESOURCEGROUP"]}\n')
        fid.write(f'export AZUREOIDC_AUTHCLAIM={secrets["AUTHCLAIM"]}\n')
        fid.write(f'export AZUREOIDC_APP_ID={app_id}\n')
        fid.write(f'export AZUREOIDC_TENANTID={tenant_id}\n')
        fid.write(f'export AZUREOIDC_AUTHPREFIX={secrets["AUTHPREFIX"]}\n')
        fid.write(f'export AZUREKMS_IDENTITY="{secrets["IDENTITY"]}"\n')
        fid.write(f'export AZUREOIDC_USERNAME="{secrets["USERNAME"]}"\n')
        fid.write(f'export AZUREOIDC_RESOURCE="{secrets["AUDIENCE"]}"\n')
        fid.write(f'export OIDC_ADMIN_USER="{secrets["USERNAME"]}"\n')
        fid.write('export OIDC_ADMIN_PWD=pwd123\n')
        fid.write(f'export MONGODB_URI="{uri}"\n')
        fid.write(f'export MONGODB_URI_SINGLE="{uri}/?{suffix}"\n')

    if os.path.exists(private_key_file):
        os.remove(private_key_file)
    with open(private_key_file, 'w') as fid:
        fid.write(b64decode(secrets['PRIVATEKEY']).decode('utf8'))
    os.chmod(private_key_file, 0o400)

    if os.path.exists(public_key_file):
        os.remove(public_key_file)
    with open(public_key_file, 'w') as fid:
        fid.write(b64decode(secrets['PUBLICKEY']).decode('utf8'))
    os.chmod(public_key_file, 0o400)

    print('Getting secrets from vault ... end')
    return secrets


if __name__ == '__main__':
    main()
