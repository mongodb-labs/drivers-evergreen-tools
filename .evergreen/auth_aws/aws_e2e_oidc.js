/**
 * Verify the AWS OIDC hosted auth works
 */
load("lib/aws_e2e_lib.js");

(function() {
"use strict";


function handleOIDCCreds() {
    const config = readSetupJson();

    const env = {
        IDP_ISSUER: config["iam_web_identity_issuer"],
        IDP_CLIENT_SECRET: config["iam_web_identity_client_secret"],
        IDP_JWKS_URI: config["iam_web_identity_jwks_uri"],
        IDP_RSA_KEY: config["iam_web_identity_rsa_key"],
        AWS_WEB_IDENTITY_TOKEN_FILE: config['iam_web_identity_token_file']
    };

    let python_command = getPython3Binary() +
        " -u lib/aws_handle_oidc_creds.py token > /dev/null"

    let ret = runShellCmdWithEnv(python_command, env);
    assert.eq(ret, 0, "Failed to write the web token");

    python_command = getPython3Binary() +
        " -u lib/aws_handle_oidc_creds.py user_id > user_id.txt"

    ret = runShellCmdWithEnv(python_command, env);
    assert.eq(ret, 0, "Failed to get the user id");

    const user_id = cat("user_id.txt");
    removeFile("user_id.txt");
    return user_id;
}

const userID = handleOIDCCreds();
print('userID');
print(userID);

const admin = Mongo().getDB("admin");
const external = admin.getMongo().getDB("$external");

assert(admin.auth("bob", "pwd123"));
const config = readSetupJson();
assert.commandWorked(external.runCommand({createUser: userID, roles:[{role: 'readWrite', db: "test"}]}));

// Note: we cannot test E2E until the mongoshell supports AWS OIDC credentials.
// const testConn = new Mongo();
// const testExternal = testConn.getDB('$external');
// assert(testExternal.auth({
//     user: credentials["AccessKeyId"],
//     pwd: credentials["SecretAccessKey"],
//     awsIamSessionToken: credentials["SessionToken"],
//     mechanism: 'OIDC'
// }));
}());
