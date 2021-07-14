/**
 * Start a KMS mock server using variables from kms_setup.json.
 *
 * To run the KMS mock server from this directory on port 8000 with a particular CA and cert file,
 * use the following bash snippet.
 *
 *   cat <<EOF > kms_setup.json
 *   {
 *      "kms_ca_file": "path/to/ca_file",
 *      "kms_cert_file": "path/to/cert_file",
 *      "port": "8000"
 *   }
 *   EOF
 *   mongo --nodb mock_kms.js
 *
 */
load("lib/kms_lib.js");

(function() {
"use strict";

// Directory containing certificates to reference for starting KMS server.
const CERT_DIRECTORY = "../x509gen/";

const config = readSetupJson();

const caFile = CERT_DIRECTORY + config["kms_ca_file"];
const certFile = CERT_DIRECTORY + config["kms_cert_file"];
const port = config["port"];

const pythonCommand = getPython3Binary() +
    ` -u lib/kms_http_server.py --ca_file ${caFile} --cert_file ${certFile} --port ${port}`;
const ret = runShellCmdWithEnv(pythonCommand, {});

assert.eq(ret, 0, "Failed to start kms mock server");
}());
