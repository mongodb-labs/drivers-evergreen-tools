#!/usr/bin/env bash
# Download gcloud CLI for Linux 64-bit (x86_64).
# Evergreen scripts must use the expansions.update command to load the expansion.
set -o errexit # Exit on first command error.

if command -v gcloud &> /dev/null; then
    echo "gcloud is on the path"
    GCPKMS_GCLOUD=gcloud
else
    echo "Download gcloud ... begin"
    wget -q https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-502.0.0-linux-x86_64.tar.gz
    tar xf google-cloud-cli-502.0.0-linux-x86_64.tar.gz
    GCPKMS_GCLOUD=$(pwd)/google-cloud-sdk/bin/gcloud
    echo "Download gcloud ... end"
fi
export GCPKMS_GCLOUD
