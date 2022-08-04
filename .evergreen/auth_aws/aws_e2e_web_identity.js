/**
 * Verify the AWS IAM EC2 hosted auth works
 */
load("lib/aws_e2e_lib.js");

(function() {
"use strict";

const ASSUMED_ROLE = "arn:aws:sts::267234750605:assumed-role/mock_idp_role/*"

function unAssignInstanceProfile() {
    const config = readSetupJson();

    const env = {
        AWS_ACCESS_KEY_ID: config["iam_auth_ec2_instance_account"],
        AWS_SECRET_ACCESS_KEY: config["iam_auth_ec2_instance_secret_access_key"],
    };
    const python_command = getPython3Binary() +
        " -u lib/aws_unassign_instance_profile.py";

    const ret = runShellCmdWithEnv(python_command, env);
    if (ret == 2) {
        print("WARNING: Request limit exceeded for AWS API");
        return false;
    }

    assert.eq(ret, 0, "Failed to assign an instance profile to the current machine");
    return true;
}

unAssignInstanceProfile();


function writeWebTokenFile() {
    const config = readSetupJson();

    const env = {
        IDP_ISSUER: config["iam_web_identity_issuer"],
        IDP_JWKS_URI: config["iam_web_identity_jwks_uri"],
        IDP_RSA_KEY: config["iam_web_identity_rsa_key"],
        AWS_WEB_IDENTITY_TOKEN_FILE: config['iam_web_identity_token_file']
    };

    const python_command = getPython3Binary() +
        " -u lib/aws_handle_oidc_creds.py token"

    const ret = runShellCmdWithEnv(python_command, env);
    assert.eq(ret, 0, "Failed to write the web token");
    return true;
}

writeWebTokenFile();


function getWebIdentityCredentials() {
    const config = readSetupJson();

    const env = {
        AWS_WEB_IDENTITY_TOKEN_FILE: config['iam_web_identity_token_file'],
        AWS_ROLE_ARN: config["iam_auth_assume_web_role_name"]
    };

    const python_command = getPython3Binary() +
        ` -u lib/aws_assume_web_role.py > creds.json`;

    const ret = runShellCmdWithEnv(python_command, env);
    assert.eq(ret, 0, "Failed to assume role on the current machine");

    const result = cat("creds.json");
    try {
        return JSON.parse(result);
    } catch (e) {
        jsTestLog("Failed to parse: " + result);
        throw e;
    }
}

const credentials = getWebIdentityCredentials();
const admin = Mongo().getDB("admin");
const external = admin.getMongo().getDB("$external");

assert(admin.auth("bob", "pwd123"));
const config = readSetupJson();
assert.commandWorked(external.runCommand({createUser: ASSUMED_ROLE, roles:[{role: 'read', db: "aws"}]}));

const testConn = new Mongo();
const testExternal = testConn.getDB('$external');
assert(testExternal.auth({
    user: credentials["AccessKeyId"],
    pwd: credentials["SecretAccessKey"],
    awsIamSessionToken: credentials["SessionToken"],
    mechanism: 'MONGODB-AWS'
}));
}());
