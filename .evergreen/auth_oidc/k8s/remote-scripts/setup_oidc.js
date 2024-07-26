/**
 * Set up OIDC auth roles.
 */
(function() {
    "use strict";

    console.log("Setting up Admin User");
    const admin = Mongo().getDB("admin");
    assert(admin.auth("bob", "pwd123"));

    console.log("Setting up OIDC User");
    const authPrefix = process.env['K8S_OIDC_AUTHPREFIX'];
    const authClaim = process.env['K8S_OIDC_CLIENT'];
    const username = `${authPrefix}/${authClaim}`

    const external = admin.getSiblingDB("$external");
    console.log('Adding user:', username);
    external.runCommand({createUser: username, roles:[{role: 'readWrite', db: 'test'}]});

    }());
