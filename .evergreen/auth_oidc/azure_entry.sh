#!/usr/bin/env bash
set -o errexit
set -o pipefail
# Do not error on unset variables. run-orchestration.sh accesses unset variables.
sudo apt-get update

echo "Install jq ... begin"
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install jq
echo "Install jq ... end"

echo "Installing MongoDB dependencies ... begin"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5
# Dependencies for run-orchestration.sh
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install python3.9-venv
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install python3-pip
# Install git.
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install git
echo "Installing MongoDB dependencies ... end"

# Run Mongo Orchestration with OIDC Enabled
export MONGODB_VERSION=latest
export TOPOLOGY=server
export ORCHESTRATION_FILE=auth-oidc.json
export DRIVERS_TOOLS=$HOME/drivers-evergreen-tools
export PROJECT_ORCHESTRATION_HOME=$DRIVERS_TOOLS/.evergreen/orchestration
export MONGO_ORCHESTRATION_HOME=$HOME
export NO_IPV6=${NO_IPV6:-""}

if [ ! -d $DRIVERS_TOOLS ]; then
    git clone https://github.com/mongodb-labs/drivers-evergreen-tools.git $DRIVERS_TOOLS
fi

cd $DRIVERS_TOOLS/.evergreen/auth_oidc
. ./activate-authoidcvenv.sh
python oidc_write_orchestration_azure.py

bash $DRIVERS_TOOLS/.evergreen/run-orchestration.sh
$DRIVERS_TOOLS/mongodb/bin/mongosh $DRIVERS_TOOLS/.evergreen/auth_oidc/setup_oidc_azure.js

# Run the Python Driver Test
cd $HOME
if [ ! -d mongo-python-driver ]; then
    git clone --branch PYTHON-3460 https://github.com/blink1073/mongo-python-driver
fi
cd mongo-python-driver
python setup.py install --no_ext
pip install requests
cd ../drivers-evergreen-tools/.evergreen/auth_oidc
python3 test_azure.py