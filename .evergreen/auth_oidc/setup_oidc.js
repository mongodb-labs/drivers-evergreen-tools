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
const role2Name = 'test2/read';

// Add the roles.
console.log('Adding role:', role1Name);
admin.runCommand({createRole: role1Name, roles:[{role: 'readWrite', db: 'test'}], privileges: []});

console.log('Adding role:', role2Name);
admin.runCommand({createRole: role2Name, roles:[{role: 'read', db: 'test'}], privileges: []});

}());
