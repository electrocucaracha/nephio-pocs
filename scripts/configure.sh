#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2024
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o pipefail
set -o errexit
set -o nounset
[[ ${DEBUG:-false} != "true" ]] || set -o xtrace

# shellcheck source=scripts/_common.sh
source _common.sh
# shellcheck source=./scripts/_utils.sh
source _utils.sh

trap get_status ERR

function _setup_sysctl {
    local key="$1"
    local value="$2"

    if [ "$(sysctl -n "$key")" != "$value" ]; then
        if [ -d /etc/sysctl.d ]; then
            echo "$key=$value" | sudo tee "/etc/sysctl.d/99-$key.conf"
        elif [ -f /etc/sysctl.conf ]; then
            echo "$key=$value" | sudo tee --append /etc/sysctl.conf
        fi

        sudo sysctl "$key=$value"
    fi
}

function _deploy_kpt_pkg {
    local pkg=$1
    local context="kind-${2:-mgmt}"
    local dest=${3:-${pkg##*/}}
    local for_deployment=${4:-false}
    local revision=${5:-main}

    [[ ! $dest =~ "/" ]] || mkdir -p "${dest%/*}"
    [ "$(ls -A "$dest")" ] || kpt pkg get "https://github.com/nephio-project/catalog.git/${pkg}@${revision}" "$dest" --for-deployment "$for_deployment"
    ! grep -qr "http://172.18.0.200:3000" "$dest" || find "$dest" -type f -exec sed -i "s|http://172.18.0.200:3000|http://$(kubectl get services gitea -n gitea --context kind-gitea -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000|g" {} \;
    newgrp docker <<BASH
    kpt fn render $dest
BASH
    kpt live init "$dest" --force
    newgrp docker <<BASH
    kpt live apply $dest --context $context
BASH
}

function _deploy_kpt_pkgs {
    local pkgs=$1
    local cluster=${2:-mgmt}

    pushd "$(mktemp -d -t "$cluster-pkg-XXX")" >/dev/null || exit
    for pkg in $pkgs; do
        _deploy_kpt_pkg "$pkg" "$cluster"
    done
    popd >/dev/null
}

function _post_cluster_creation {
    local cluster=$1

    sudo cp /root/.kube/config "$HOME/.kube/config"
    sudo chown -R "$USER" "$HOME/.kube/"
    chmod 600 "$HOME/.kube/config"

    kubectl label node kind-control-plane node.kubernetes.io/exclude-from-external-load-balancers- || true

    # Wait for node readiness
    for node in $(kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' --context "kind-$cluster"); do
        kubectl wait --for=condition=ready "node/$node" --context "kind-$cluster"
    done
}

# Increase inotify resources
_setup_sysctl "fs.inotify.max_user_watches" "524288"
_setup_sysctl "fs.inotify.max_user_instances" "512"

mkdir -p "$HOME/.kube"

pushd "$(git rev-parse --show-toplevel)" >/dev/null
sudo docker compose up --detach
popd >/dev/null

# Deploy Gitea cluster
if ! sudo kind get clusters | grep -q gitea; then
    sudo kind create cluster --name gitea --image kindest/node:v1.26.3
    _post_cluster_creation gitea
fi
_deploy_kpt_pkgs "distros/sandbox/gitea" "gitea"

# Deploy Nephio Management + Cluster API cluster
if ! sudo kind get clusters | grep -q mgmt; then
    cat <<EOF | sudo kind create cluster --name mgmt --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.26.3
    extraMounts:
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
    extraPortMappings:
      - containerPort: 30086
        hostPort: 16686
EOF
    _post_cluster_creation mgmt
fi

# Wait for Gitea service readiness
kubectl rollout status deployment gitea-memcached -n gitea --context kind-gitea

# Create secret to connect to Gitea services
kubectl create namespace gitea
kubectl apply -f https://raw.githubusercontent.com/nephio-project/catalog/main/distros/sandbox/gitea/secret-git-user.yaml

# Deploy Nephio Management components
pkgs=""
[ "${ENABLE_CLUSTER_API:-false}" == "true" ] && pkgs+="distros/sandbox/cert-manager infra/capi/cluster-capi infra/capi/cluster-capi-infrastructure-docker infra/capi/cluster-capi-kind-docker-templates "
[ "${ENABLE_PORCH:-true}" == "true" ] && pkgs+="nephio/core/porch "
[ "${ENABLE_NEPHIO_OPERATOR:-true}" == "true" ] && pkgs+="nephio/core/nephio-operator nephio/optional/resource-backend "
[ "${ENABLE_CONFIGSYNC:-true}" == "true" ] && pkgs+="nephio/core/configsync "              # Required for access tokens to connect to gitea services
[ "${ENABLE_NETWORK_CONFIG:-false}" == "true" ] && pkgs+="nephio/optional/network-config " # Required for workload cluster provisioning process

_deploy_kpt_pkgs "$pkgs"

# Rootsync objects configure ConfigSync to watch the specified source and apply objects from that source to the cluster.
_deploy_kpt_pkg "nephio/optional/rootsync" "mgmt" "/tmp/optional/mgmt" "true"

# Manage the contents of the Management clusters
_deploy_kpt_pkg "distros/sandbox/repository" "mgmt" "/tmp/repository/mgmt" "true"

# Used internally during the cluster bootstrapping process
_deploy_kpt_pkg "distros/sandbox/repository" "mgmt" "/tmp/repository/mgmt-staging" "true"

# Register repositories required for Workload Nephio cluster package operation
_deploy_kpt_pkgs "nephio/optional/stock-repos"

if [ "${ENABLE_PORCH_DEV:-true}" == "true" ]; then
    kubectl apply -f https://raw.githubusercontent.com/nephio-project/porch/main/deployments/tracing/deployment.yaml
    kubectl patch deployment porch-server -n porch-system --type 'json' -p '[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "OTEL", "value": "otel://jaeger-oltp:4317"}}]'
    KUBE_EDITOR='sed -i "s|  type\: .*|  type\: NodePort|g"' kubectl edit service -n porch-system jaeger-http
    KUBE_EDITOR='sed -i "s|  - nodePort\: .*|  - nodePort: 30086|g"' kubectl edit service -n porch-system jaeger-http
fi
