/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));
assert.deepEqual({ ok: 1 }, admin.runCommand({createRole: 'test1/readWrite', roles:[{role: 'readWrite', db: 'test'}], privileges: []}));
assert.deepEqual({ ok: 1 }, admin.runCommand({createRole: 'test2/read', roles:[{role: 'read', db: 'test'}], privileges: []}));

}());
