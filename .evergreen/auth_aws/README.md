# Configuration Scripts for End-to-end Testing

These scripts were originally taken from [mongo-enterprise-modules](https://github.com/10gen/mongo-enterprise-modules/tree/master/jstests/external_auth_aws)
and intended to simplify creating users, attaching roles to existing EC2 instances, launching an Amazon ECS container instance, etc.

## Test Process

For all testing variants except for ECS, the general test flow is:

- Set up the required secrets for the the test variant:

```bash
# Fetch the secrets from the vault and write to a `secrets-export.sh` file in the $DRIVERS_TOOLS/.evergreen/auth_aws directory.
bash $DRIVERS_TOOLS/.evergreen/auth_aws/setup-secrets.sh
```

See [Secrets Handling](../secrets_handling/README.md) for details on how to access the secrets 
from the `drivers/auth_aws` vault using the `setup-secrets.sh` script in th  `$DRIVERS_TOOLS/.evergreen/auth_aws` directory.

- Run the setup for the test variant and then run your specific tests.

```bash
cd $DRIVERS_TOOLS/.evergreen/auth_aws
# Create a python virtual environment.
. ./activate-authawsvenv.sh
# Source the environment variables. Configure the environment and the server.
. aws_setup.sh <variant>
# Run your driver-specific tests here.
```

It is recommended that these actions be broken into scripts that can be run locally as well as in CI.  The instructions
for setting up local secrets handling are in the wiki page.

## ECS Test Process

The ECS test variant requires a slightly different approach, since we need to run the code in a container.

Set up a `run-mongodb-aws-ecs-test.sh` script that will run on the container.  This script should be
copied to `${DRIVERS_TOOLS}/.evergreen/auth_aws/src/.evergreen`.  The driver code and test code should
be compiled if necessary, and then compressed into a `src.tgz` file that will be expanded and used in
the container.

```bash
# Set up the target directory.
ECS_SRC_DIR=${DRIVERS_TOOLS}/.evergreen/auth_aws/src
mkdir -p $ECS_SRC_DIR/.evergreen
# Move the test script to the correct location.
cp ${PROJECT_DIRECTORY}/.evergreen/run-mongodb-aws-ecs-test.sh $ECS_SRC_DIR/.evergreen
# Driver-specific - compile/build code if needed.
# Driver-specific - move artifacts needed for test to $ECS_SRC_DIR
# Run the test
PROJECT_DIRECTORY="$ECS_SRC_DIR" MONGODB_BINARIES="/path/to/mongodb/bin" $AUTH_AWS_DIR/aws_setup.sh ecs
```

## Deprecated Scripts

The top-level JavaScript files in this directory are deprecated and no longer needed when
using the instructions above. They use the legacy `mongo` shell.
Additionally, it is not longer required to create
an `aws_e2e_setup.json` file using Evergreen project variables.  The variables are
single-sourced from AWS Secrets Manager.
