# Download gcloud CLI for Linux 64-bit (x86_64).
# On success, a gcloud-expansions.yml file is created with the expansion GCLOUD to the gcloud binary.
# Evergreen scripts must use the expansions.update command to load the expansion.
set -o errexit # Exit on first command error.

echo "Download gcloud ... begin"
wget https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-393.0.0-linux-x86_64.tar.gz
tar xf google-cloud-cli-393.0.0-linux-x86_64.tar.gz
GCLOUD=$(pwd)/google-cloud-sdk/bin/gcloud
echo "GCLOUD: $GCLOUD" > gcloud-expansions.yml
echo "Download gcloud ... end"