/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));

console.log("Setting up User");
const authorizationPrefix = process.env['AZUREOIDC_AUTHPREFIX'] || 'test1';
const authorizationClaim = process.env['AZUREOIDC_AUTHCLAIM'] || 'readWrite';
const role1Name = authorizationPrefix + '/' + authorizationClaim;
const authorizationPrefix2 = process.env['AZUREOIDC_AUTHPREFIX2'] || 'test2';
const authorizationClaim2 = process.env['AZUREOIDC_AUTHCLAIM2'] || 'read';
const role2Name = authorizationPrefix2 + '/' + authorizationClaim2;

// Add the roles.
console.log('Adding role:', role1Name);
admin.runCommand({createRole: role1Name, roles:[{role: authorizationClaim, db: 'test'}], privileges: []});

console.log('Adding role:', role2Name);
admin.runCommand({createRole: role2Name, roles:[{role: authorizationClaim2, db: 'test'}], privileges: []});

}());
