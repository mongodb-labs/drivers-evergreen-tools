/**
 * Verify the AWS IAM ECS hosted auth works
 */

(function() {
"use strict";

// This varies based on hosting ECS task as the account id and role name can vary
const AWS_ACCOUNT_ARN = "arn:aws:sts::557821124784:assumed-role/ecsTaskExecutionRole/*";
const AWS_ACCOUNT_ARN2 = "arn:aws:iam::557821124784:user/authtest_fargate_user";

const external = Mongo().getDB("$external");
const admin = Mongo().getDB("admin");

admin.runCommand({createUser: "admin", pwd: "pwd", roles: ['root']});

console.log("Adding user:", AWS_ACCOUNT_ARN)
external.runCommand({createUser: AWS_ACCOUNT_ARN, roles:[{role: 'read', db: "aws"}]});
// console.log("Adding user:", AWS_ACCOUNT_ARN2)
// external.runCommand({createUser: AWS_ACCOUNT_ARN2, roles:[{role: 'read', db: "aws"}]});

// Try the auth function
const testConn = new Mongo();
const testExternal = testConn.getDB('$external');
assert(testExternal.auth({mechanism: 'MONGODB-AWS'}));
}());
