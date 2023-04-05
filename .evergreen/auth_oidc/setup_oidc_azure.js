/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));

const authorizationClaim = process.env('AZUREOIDC_AUTH_CLAIM');

// Add the role.
admin.runCommand({createRole: 'OIDC_test/' + authorizationClaim, roles:[{role: 'readWrite', db: 'test'}], privileges: []});

}());
