# Azure Function Code

Scripts to handle testing an OIDC on Azure Functions.

https://learn.microsoft.com/en-us/azure/azure-functions/

## Prerequisites

### Overall
- Admin creates an Application in Azure
- Admin adds an Application URL to the Application
- Admin creates a Resource Group
- Admin creates a managed identity in the Resource Group
- Admin adds a role of "Managed Identity Operator" for the Application in the Resource Group
- Admin creates an Identity Provider in Atlas Cloud-Dev that has the following fields:
    - iss: https://sts.windows.net/<subscription>
    - aud: <application-url>
- Admin adds the Identity Provider to the Project
- Admin creates a Database User for the IdP:
    - sub: <managed-identity-client-id>
- Admin creates a storage account in the resource group

### Per Driver

- Admin creates a Function App for the driver in the shared resource group
    - Choose "Consumption" plan
    - Create a unique name for the driver
    - Choose the appropriate Runtime stack and version for the driver
- Admin adds the managed identity as a User-assigned identity on the Function App
- Admin adds the "Contributor" privileged role for the application in the Function App
- Admin adds environment variable for RESOURCE and CLIENT_ID.
- Admin adds the team member as a "Contributor" to the Function App
- Admin gives the function name to the driver team

- Driver team runs the following to set up a local function instance:
    - Follow the quick-start instructions for [Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/)
    - Stop at the "Create supporting Azure resources" stage, since they were created by the Admin
    - Run the login.sh script
    - Run `func azure functionapp publish <func-name>` and verify that it deploys
    - Run the invoke script and verify that it invokes


## Self-Test

There is a self-test that runs during setup that invokes the `oidcselftest` function in the `$AZUREOIDC_FUNC_SELF_TEST` Function App
that is run durint setup.

You can also manually invoke the `gettoken` function by running the following:

```bash
source ./secrets-export.sh
pushd self-test
export FUNC_NAME=gettoken
export FUNC_APP_NAME=$AZUREOIDC_FUNC_SELF_TEST
bash ../run-driver-test.sh
popd
```

## Driver Test

Drivers should use a task group to ensure resources are properly torn down.  An example is as follows:

```yaml
- name: testoidc_azure_func_task_group
  setup_group_can_fail_task: true
  setup_group_timeout_secs: 1800
  teardown_group_can_fail_task: true
  teardown_group_timeout_secs: 1800
  setup_group:
    - func: fetch source
    - func: other setup function
    - command: subprocess.exec
      params:
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/azure_func/setup.sh
  teardown_group:
    - command: subprocess.exec
      params:
        binary: bash
        args:
          - ${DRIVERS_TOOLS}/.evergreen/auth_oidc/azure_func/teardown.sh
    - func: other teardown function
  tasks:
    - oidc-auth-test-azure-func
```

Where the test func does something like the following:

```bash
pushd <driver-oidc-func-dir>
export FUNC_NAME=<driver-oidc-func-test>
export FUNC_APP_NAME=${DRIVER_FUNC_FROM_ENVIRONMENT}
bash ${DRIVERS_TOOLS/.evergreen/auth_oidc/azure_func/run-driver-test.sh
popd
```

The <driver-oidc-func-dir> should contain an Azure function that runs a write operation
on a driver similar to the following:

```python
@app.route(route='pythonoidctest')
def oidcselftest(req: func.HttpRequest) -> func.HttpResponse:
    resource=os.environ['APPSETTING_RESOURCE']
    client_id= os.environ['APPSETTING_CLIENT_ID']
    req_body = req.get_json()
    uri = req_body.get('MONGODB_URI')
    props = dict(ENVIRONMENT='azure', TOKEN_RESOURCE=resource)
    client = MongoClient(uri, username=client_id, authMechanism="MONGODB-OIDC", authMechanismProperties=props)
    c.test.test.insert_one({})
    c.close()
    return func.HttpResponse('Success!')
```
