/**
 * Set up OIDC auth roles.
 */
load("lib/aws_e2e_lib.js");

(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));
const config = readSetupJson();
assert.commandWorked(admin.runCommand({createRole: 'test1/readWrite', roles:[{role: 'readWrite', db: "test"}], privileges: []}));
assert.commandWorked(admin.runCommand({createRole: 'test2/read', roles:[{role: 'read', db: "test"}], privileges: []}));

}());
