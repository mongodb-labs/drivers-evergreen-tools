/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));

console.log("Setting up User");
const authorizationPrefix = process.env['OIDC_AUTH_PREFIX'] || 'test1';
const authorizationClaim = process.env['OIDC_AUTH_CLAIM'] || 'readWrite';
const roleName = authorizationPrefix + '/' + authorizationClaim;
console.log('adding role:', roleName);

// Add the roles.
admin.runCommand({createRole: roleName, roles:[{role: 'readWrite', db: 'test'}], privileges: []});
admin.runCommand({createRole: 'test2/read', roles:[{role: 'read', db: 'test'}], privileges: []});

}());
