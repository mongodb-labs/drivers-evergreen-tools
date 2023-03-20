/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const admin = Mongo().getDB("admin");
assert(admin.auth("bob", "pwd123"));
admin.runCommand({createRole: 'test1/readWrite', roles:[{role: 'readWrite', db: 'test'}], privileges: []});
admin.runCommand({createRole: 'test2/read', roles:[{role: 'read', db: 'test'}], privileges: []});

// Wait for the node to be primary.
while (true) {
    try {
        if (admin.runCommand('replSetGetStatus').myState == 1) {
            break;
        }
    } catch (e) {
        console.log(e);
    }
    sleep(500);
}

exit();

}());
