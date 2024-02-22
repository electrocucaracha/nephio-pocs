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
    local dest=${2:-${pkg##*/}}
    local revision=${3:-main}

    [[ ! $dest =~ "/" ]] || mkdir -p "${dest%/*}"
    kpt pkg get "https://github.com/nephio-project/catalog.git/${pkg}@${revision}" "$dest" --for-deployment "${4:-false}"
    newgrp docker <<BASH
    kpt fn render $dest
BASH
    kpt live init "$dest"
    newgrp docker <<BASH
    kpt live apply $dest
BASH
}

# Increase inotify resources
_setup_sysctl "fs.inotify.max_user_watches" "524288"
_setup_sysctl "fs.inotify.max_user_instances" "512"

# Deploy Nephio Management cluster
if ! sudo kind get clusters | grep -q kind; then
    cat <<EOF | sudo kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.26.3
    extraMounts:
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
EOF
    mkdir -p "$HOME/.kube"
    sudo cp /root/.kube/config "$HOME/.kube/config"
    sudo chown -R "$USER" "$HOME/.kube/"
    chmod 600 "$HOME/.kube/config"
fi

# Deploy Nephio Management components
pushd "$(mktemp -d -t "mgmt-pkg-XXX")" >/dev/null || exit
pkgs=""
[ "${ENABLE_METALLB:-true}" == "true" ] && pkgs+="distros/sandbox/metallb distros/sandbox/metallb-sandbox-config "
[ "${ENABLE_GITEA:-true}" == "true" ] && pkgs+="distros/sandbox/gitea "
[ "${ENABLE_CLUSTER_API:-false}" == "true" ] && pkgs+="distros/sandbox/cert-manager infra/capi/cluster-capi infra/capi/cluster-capi-infrastructure-docker infra/capi/cluster-capi-kind-docker-templates "
[ "${ENABLE_PORCH:-true}" == "true" ] && pkgs+="nephio/core/porch "
[ "${ENABLE_NEPHIO_OPERATOR:-true}" == "true" ] && pkgs+="nephio/core/nephio-operator "
[ "${ENABLE_CONFIGSYNC:-true}" == "true" ] && pkgs+="nephio/core/configsync "              # Required for access tokens to connect to gitea services
[ "${ENABLE_NETWORK_CONFIG:-false}" == "true" ] && pkgs+="nephio/optional/network-config " # Required for workload cluster provisioning process

for pkg in $pkgs; do
    _deploy_kpt_pkg "$pkg"
done
popd >/dev/null

# Rootsync objects configure ConfigSync to watch the specified source and apply objects from that source to the cluster.
_deploy_kpt_pkg "nephio/optional/rootsync" "/tmp/optional/mgmt" "main" "true"

# Manage the contents of the Management clusters
_deploy_kpt_pkg "distros/sandbox/repository" "/tmp/repository/mgmt" "main" "true"

# Used internally during the cluster bootstrapping process
_deploy_kpt_pkg "distros/sandbox/repository" "/tmp/repository/mgmt-staging" "main" "true"

# Register repositories required for Workload Nephio cluster package operation
for repo in "-infra-capi" "-nephio-core" "-distros-sandbox" "-nephio-optional"; do
    cat <<EOF | kubectl apply -f -
apiVersion: config.porch.kpt.dev/v1alpha1
kind: Repository
metadata:
  name: catalog$repo
  namespace: default
  labels:
    kpt.dev/repository-access: read-only
    kpt.dev/repository-content: external-blueprints
spec:
  content: Package
  git:
    branch: main
    directory: ${repo//-/\/}
    repo: https://github.com/nephio-project/catalog.git
  type: git
EOF
done
