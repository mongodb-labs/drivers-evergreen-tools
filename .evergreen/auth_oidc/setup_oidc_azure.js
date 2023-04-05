/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));

console.log("Setting up User");
const authorizationClaim = process.env['AZUREOIDC_AUTH_CLAIM'];
console.log("authorizationClaim: ", authorizationClaim);

// Add the role.
admin.runCommand({createRole: 'OIDC_test/' + authorizationClaim, roles:[{role: 'readWrite', db: 'test'}], privileges: []});

}());
