/**
 * Verify the AWS IAM ECS hosted auth works
 */

(function() {
"use strict";

// This varies based on hosting ECS task as the account id and role name can vary
const AWS_ACCOUNT_ARN = "arn:aws:iam::557821124784:user/authtest_fargate_user";

const external = Mongo().getDB("$external");
const admin = Mongo().getDB("admin");

// Add standard admin.
admin.runCommand({createUser: "bob", pwd: "pwd123", roles: ['root']});

// Add other admin for backwards compatibility.
admin.runCommand({createUser: "admin", pwd: "pwd", roles: ['root']});

admin.auth("bob", "pwd123");

external.runCommand({createUser: AWS_ACCOUNT_ARN, roles:[{role: 'read', db: "aws"}]});

// Try the auth function
const testConn = new Mongo();
const testExternal = testConn.getDB('$external');
assert(testExternal.auth({mechanism: 'MONGODB-AWS'}));
}());
