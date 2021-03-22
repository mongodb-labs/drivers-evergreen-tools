/**
 * Start a KMS mock server using variables from kms_setup.json
 */
load("lib/kms_lib.js");

(function() {
"use strict";

// Directory containing certificates to reference for starting KMS server.
const CERT_DIRECTORY = "../x509gen/";

const config = readSetupJson();

const caFile = CERT_DIRECTORY + config["kms_ca_file"];
const certFile = CERT_DIRECTORY + config["kms_cert_file"];

const pythonCommand = getPython3Binary() +
    ` -u lib/kms_http_server.py --ca_file ${caFile} --cert_file ${certFile}`;
const ret = runShellCmdWithEnv(pythonCommand, {});

assert.eq(ret, 0, "Failed to start kms mock server");
}());
