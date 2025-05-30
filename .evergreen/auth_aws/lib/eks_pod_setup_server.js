(function() {
"use strict";

const AWS_ACCOUNT_ARN=process.env["MONGODB_AWS_ACCOUNT_ARN"];
const admin = Mongo().getDB("admin");
const external = admin.getMongo().getDB("$external");
assert(admin.auth("bob", "pwd123"));

external.runCommand({createUser: AWS_ACCOUNT_ARN, roles:[{role: 'read', db: "aws"}]});
}());
