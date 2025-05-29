#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

_SCRIPT_DIR=$SCRIPT_DIR
source $SCRIPT_DIR/../../k8s/eks/secrets-export.sh

NAME="$1"
MONGODB_URI="mongodb://${NAME}:27017"
APP_LABEL=mongodb-deployment

. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl

# Delete mongodb servers over one hour old in case they were not torn down.
echo "Deleting old mongodb servers..."
if [ "$(uname -s)" = "Darwin" ]; then
    DATE="gdate"
else
    DATE="date"
fi
# shellcheck disable=SC2046
kubectl get deployments -l app=$APP_LABEL -o go-template --template '{{range .items}}{{.metadata.name}} {{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | awk '$2 <= "'$($DATE -d'now-1 hours' -Ins --utc | sed 's/+0000/Z/')'" { print $1 }' | xargs --no-run-if-empty kubectl delete deployment
# shellcheck disable=SC2046
kubectl get services -l app=$APP_LABEL -o go-template --template '{{range .items}}{{.metadata.name}} {{.metadata.creationTimestamp}}{{"\n"}}{{end}}' | awk '$2 <= "'$($DATE -d'now-1 hours' -Ins --utc | sed 's/+0000/Z/')'" { print $1 }' | xargs --no-run-if-empty kubectl delete service
echo "Deleting old mongodb servers... done."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  labels:
    app: ${APP_LABEL}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      containers:
      - name: mongodb
        image: mongodb/mongodb-enterprise-server:latest
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: "bob"
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: "pwd123"
        - name: MONGODB_AWS_ACCOUNT_ARN
          value: "${EKS_ROLE_ARN}"
        args:
        - "--setParameter"
        - "authenticationMechanisms=MONGODB-AWS,SCRAM-SHA-256"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  labels:
    app: ${APP_LABEL}
spec:
  selector:
    app: ${NAME}
  ports:
  - protocol: TCP
    port: 27017
    targetPort: 27017
  type: ClusterIP
EOF

pushd $_SCRIPT_DIR

# Set up the server.
echo "Setting up the server..."
set -x
MONGODB_POD=$(kubectl get pods -l app=${NAME} -o jsonpath='{.items[0].metadata.name}')
# Wait for the pod to be ready.
kubectl wait --for=condition=Ready pod/${MONGODB_POD} --timeout=2000s
kubectl exec ${MONGODB_POD} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ./eks_pod_setup_server.js ${MONGODB_POD}:/tmp/test/setup_server.js
kubectl exec ${MONGODB_POD} -- mongosh /tmp/test/setup_server.js
echo "Setting up the server... done."

# Run the self test.
echo "Running self test on eks pod..."
kubectl exec ${K8S_POD_NAME} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ./eks-pod-run-self-test.sh ${K8S_POD_NAME}:/tmp/test/run-self-test.sh
kubectl cp ./eks_pod_self_test.py ${K8S_POD_NAME}:/tmp/test/test.py
kubectl exec ${K8S_POD_NAME} -- /tmp/test/run-self-test.sh $MONGODB_URI
echo "Running self test on eks pod... done."

popd
