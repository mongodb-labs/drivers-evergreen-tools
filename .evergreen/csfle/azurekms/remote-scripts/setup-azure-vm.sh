echo "Install jq ... begin"
sudo apt-get install jq -y
echo "Install jq ... end"

echo "Installing MongoDB dependencies ... begin"
# Dependencies for mongod: https://www.mongodb.com/docs/manual/tutorial/install-mongodb-enterprise-on-debian-tarball/
sudo apt-get -y install libcurl4 libgssapi-krb5-2 libldap-2.4-2 libwrap0 libsasl2-2 libsasl2-modules libsasl2-modules-gssapi-mit snmp openssl liblzma5
# Dependencies for run-orchestration.sh
sudo apt-get -y install virtualenv
sudo apt-get -y install python3-pip
# Install git.
sudo apt-get -y install git
echo "Installing MongoDB dependencies ... end"

echo "Starting MongoDB server ... begin"
git clone https://github.com/mongodb-labs/drivers-evergreen-tools
export DRIVERS_TOOLS=$(pwd)/drivers-evergreen-tools
export MONGO_ORCHESTRATION_HOME="$DRIVERS_TOOLS/.evergreen/orchestration"
export MONGODB_BINARIES="$DRIVERS_TOOLS/mongodb/bin"
echo "{ \"releases\": { \"default\": \"$MONGODB_BINARIES\" }}" > $MONGO_ORCHESTRATION_HOME/orchestration.config
# Use run-orchestration with defaults.
sh ${DRIVERS_TOOLS}/.evergreen/run-orchestration.sh
echo "Starting MongoDB server ... end"
