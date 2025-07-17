#!/usr/bin/env bash
set -eu

# Write the secrets-export.sh file to the k8s/eks directory.
EKS_DIR="../../k8s/eks"

cat <<EOF >> $EKS_DIR/secrets-export.sh
export EKS_CLUSTER_NAME=$EKS_CLUSTER_NAME
export EKS_SERVICE_ACCOUNT_NAME=$EKS_SERVICE_ACCOUNT_NAME
export EKS_REGION=$EKS_REGION
EOF

bash $EKS_DIR/setup.sh
source $EKS_DIR/secrets-export.sh

NAME="$1"
MONGODB_URI="mongodb://${NAME}:27017"
APP_LABEL=mongodb-deployment
MONGODB_VERSION=${MONGODB_VERSION:-latest}

. ../../ensure-binary.sh kubectl

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
        image: mongodb/mongodb-enterprise-server:${MONGODB_VERSION}
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

# Set up the server.
echo "Setting up the server..."
MONGODB_POD=$(kubectl get pods -l app=${NAME} -o jsonpath='{.items[0].metadata.name}')
# Wait for the pod to be ready.
kubectl wait --for=condition=Ready pod/${MONGODB_POD} --timeout=2000s
kubectl exec ${MONGODB_POD} -- bash -c "rm -rf /tmp/test && mkdir /tmp/test"
kubectl cp ./eks_pod_setup_server.js ${MONGODB_POD}:/tmp/test/setup_server.js
kubectl exec ${MONGODB_POD} -- mongosh /tmp/test/setup_server.js
echo "Setting up the server... done."

# Run the self test.
echo "Running self test on eks pod..."
kubectl exec ${MONGODB_POD} -- bash -c "rm -rf /tmp/self-test && mkdir /tmp/self-test"
kubectl cp ./eks-pod-run-self-test.sh ${MONGODB_POD}:/tmp/self-test/run-self-test.sh
kubectl cp ./eks_pod_self_test.py ${MONGODB_POD}:/tmp/self-test/test.py
kubectl exec ${MONGODB_POD} -- /tmp/self-test/run-self-test.sh $MONGODB_URI
echo "Running self test on eks pod... done."

# Set up driver test.
echo "Setting up driver test files..."
kubectl exec ${MONGODB_POD} -- bash -c "rm -rf /tmp/src"
kubectl cp $PROJECT_DIRECTORY ${MONGODB_POD}:/tmp/src/
echo "Setting up driver test files... done."

echo "Running the driver test command... done."
echo "export MONGODB_URI=${MONGODB_URI}" >> secrets-export.sh
kubectl cp ./secrets-export.sh ${MONGODB_POD}:/tmp/src/secrets-export.sh
echo "Setting up driver test files... done."

# Run the driver test.
echo "Running the driver test command..."
MONGODB_URI="${MONGODB_URI}/aws?authMechanism=MONGODB-AWS"
kubectl exec ${MONGODB_POD} -- bash -c "cd /tmp && source src/secrets-export.sh && bash src/.evergreen/run-mongodb-aws-eks-test.sh $MONGODB_URI"
echo "Running the driver test command... done."
