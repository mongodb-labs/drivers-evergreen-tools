#!/bin/sh

# Delete the GCE instance after a period of time.
# Refer: https://cloud.google.com/community/tutorials/create-a-self-deleting-virtual-machine
sleep 7200
export NAME=$(curl -X GET http://metadata.google.internal/computeMetadata/v1/instance/name -H 'Metadata-Flavor: Google')
export ZONE=$(curl -X GET http://metadata.google.internal/computeMetadata/v1/instance/zone -H 'Metadata-Flavor: Google')
gcloud --quiet compute instances delete $NAME --zone=$ZONE
