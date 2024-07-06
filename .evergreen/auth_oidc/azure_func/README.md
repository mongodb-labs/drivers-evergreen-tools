
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

The login.sh script will: get the creds and log in to azure
The setup.sh script will: Launch Atlas cluster and set up cli and login
The invoke.sh script will: invoke the script.  It takes a FUNC_APP_NAME, FUNC_NAME and optional MONGODB_URI.
The run-driver-test.sh script will: Publish the app and invoke it in the current directory.  It takes a FUNC_APP_NAME, FUNC_NAME and MONGODB_URI.

TODO: Have two built-in test apps:
- First one returns a token
- Second on connects to Atlas
