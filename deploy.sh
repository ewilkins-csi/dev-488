#!/bin/sh

APP_NAME=dev-488
INFRA_NAME=infrastructure

print_usage() {
  echo "Usage: $0 [up|down|shutdown]"
  echo "   up          deploy application (automatically starts deployment infrastructure if needed)"
  echo "   down        tear down application"
  echo "   shutdown    tear down deployment infrastructure"
}

startup() {
  echo "Checking for deployment infrastructure..."
  helm status $INFRA_NAME > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    helm upgrade --install $INFRA_NAME dev-488-infrastructure \
      --values dev-488-infrastructure/values.yaml \
      --values dev-488-infrastructure/values-dev.yaml
    if ! kubectl wait -A --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server; then
      exit $?
    fi
    argocd repo add https://github.com/ewilkins-csi/dev-488 --server localhost:30080 --plaintext --insecure-skip-server-verification
  fi
}

is_app_running() {
  argocd app get $APP_NAME --server localhost:30080 --plaintext > /dev/null 2>&1
}

deploy() {
  startup

  if is_app_running; then
    echo "dev-488 is deployed"
  else
    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Deploying dev-488 from branch '$branch'..."
    argocd app create $APP_NAME \
      --server localhost:30080 --plaintext \
      --dest-namespace dev-488 \
      --dest-server https://kubernetes.default.svc \
      --repo https://github.com/ewilkins-csi/dev-488 \
      --path dev-488-deploy/src/main/resources \
      --revision $branch \
      --helm-set spec.targetRevision=$branch \
      --values values.yaml \
      --values values-dev.yaml \
      --sync-policy automated
  fi
}

down() {
  if is_app_running; then
    echo "Tearing down app..."
    argocd app delete $APP_NAME --server localhost:30080 --plaintext --yes
  else
    echo "dev-488 is not deployed"
  fi
}

shutdown() {
  helm status $INFRA_NAME > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Infrastructure already shutdown"
  else
    if is_app_running; then
      down
    fi
    echo "Shutting down infrastructure..."
    helm uninstall $INFRA_NAME
  fi
}


if [ "$1" = "up" ]; then
  deploy
elif [ "$1" = "down" ]; then
  down
elif [ "$1" = "shutdown" ]; then
  shutdown
else
  print_usage
fi