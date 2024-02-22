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

# TODO: Use https://github.com/kubernetes/kubernetes/pull/122994 when it's available
# k8s_wait_exists() - Waits for the creation of a given kubernetes resource
function k8s_wait_exists {
    local resource_type=$1
    local resource_name=$2
    local kubeconfig=${3:-"$HOME/.kube/config"}
    local resource_namespace=${4:-default}
    local timeout=${5:-600}
    timeout=600

    info "looking for $resource_type $resource_namespace/$resource_name using $kubeconfig"
    local found=""
    while [[ $timeout -gt 0 ]]; do
        found=$(kubectl --kubeconfig "$kubeconfig" -n "$resource_namespace" get "$resource_type" "$resource_name" -o jsonpath='{.metadata.name}' --ignore-not-found)
        if [[ $found ]]; then
            return
        fi
        timeout=$((timeout - 5))
        sleep 5
    done

    kubectl --kubeconfig "$kubeconfig" -n "$resource_namespace" get "$resource_type"
    error "Timed out waiting for $resource_type $resource_namespace/$resource_name"
}

# k8s_wait_ready() - Waits for the readiness of a given kubernetes resource
function k8s_wait_ready {
    local resource_type=$1
    local resource_name=$2
    local kubeconfig=${3:-"$HOME/.kube/config"}
    local resource_namespace=${4:-default}
    local timeout=${5:-600}

    k8s_wait_exists "$@"

    info "checking readiness of $resource_type $resource_namespace/$resource_name using $kubeconfig"
    kubectl wait --for condition=Ready "$resource_type" "$resource_name" -n "$resource_namespace" --kubeconfig "$kubeconfig" --timeout "${timeout}s"
}

# k8s_get_capi_kubeconfig() - Gets the Kubeconfig file for a given Cluster API cluster
function k8s_get_capi_kubeconfig {
    local cluster=$1
    local file="/tmp/${cluster}-kubeconfig"

    if [ ! -f "$file" ]; then
        k8s_wait_exists "secret" "${cluster}-kubeconfig" >/dev/null 2>&1
        kubectl --kubeconfig "$HOME/.kube/config" get secret "${cluster}-kubeconfig" -o jsonpath='{.data.value}' | base64 -d >"$file"
    fi
    echo "$file"
}

# k8s_wait_ready_replicas() - Waits for the readiness of a minimum number of replicas
function k8s_wait_ready_replicas {
    local resource_type=$1
    local resource_name=$2
    local kubeconfig=${3:-"$HOME/.kube/config"}
    local resource_namespace=${4:-default}

    timeout=600
    min_ready=1
    status_field=readyReplicas
    [ "$resource_type" != "daemonset" ] || status_field=numberReady

    # should validate the params...
    [ -f "$kubeconfig" ] || error "Kubeconfig file doesn't exist"

    k8s_wait_exists "$resource_type" "$resource_name" "$kubeconfig" "$resource_namespace" "$timeout"

    info "checking readiness of $resource_type $resource_namespace/$resource_name using $kubeconfig"
    local ready=""
    while [[ $timeout -gt 0 ]]; do
        ready=$(kubectl --kubeconfig "$kubeconfig" -n "$resource_namespace" get "$resource_type" "$resource_name" -o jsonpath="{.status.$status_field}" || echo)
        if [[ $ready -ge $min_ready ]]; then
            return
        fi
        timeout=$((timeout - 5))
        sleep 5
    done

    kubectl --kubeconfig "$kubeconfig" -n "$resource_namespace" describe "$resource_type" "$resource_name"
    error "Timed out waiting for $resource_type $resource_namespace/$resource_name to be ready"
}

# capi_cluster_ready() - Wait for Cluster API cluster service readiness
function capi_cluster_ready {
    local cluster=$1

    k8s_wait_ready "cl" "$cluster"
    for machineset in $(kubectl get machineset -l cluster.x-k8s.io/cluster-name="$cluster" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
        k8s_wait_ready "machineset" "$machineset"
    done

    # Wait for package variants
    for pv in cluster configsync kindnet local-path-provisioner multus repo rootsync vlanindex; do
        k8s_wait_exists "packagevariants" "${cluster}-$pv"
    done

    # Wait for deployments and daemonsets readiness
    kubeconfig=$(k8s_get_capi_kubeconfig "$cluster")
    k8s_wait_ready_replicas "deployment" "otel-collector" "$kubeconfig" "config-management-monitoring"
    for deploy in config-management-operator reconciler-manager "root-reconciler-$cluster"; do
        k8s_wait_ready_replicas "deployment" "$deploy" "$kubeconfig" "config-management-system"
    done
    k8s_wait_ready_replicas "deployment" "local-path-provisioner" "$kubeconfig" "local-path-storage"
    k8s_wait_ready_replicas "daemonset" "kindnet" "$kubeconfig" "kube-system"
    k8s_wait_ready_replicas "daemonset" "kube-multus-ds" "$kubeconfig" "kube-system"
}

kpt alpha repo get oai-core-packages || kpt alpha repo reg https://github.com/OPENAIRINTERFACE/oai-packages.git --name oai-core-packages --branch r2 --namespace default
kubectl apply -f infra.yaml

# Wait for cluster resources creation
k8s_wait_exists "workloadcluster" "core01"
k8s_wait_exists "packagevariant" "kcd-clusters-mgmt-core01"
k8s_wait_exists "cl" "core01"

# Wait for cluster readiness
capi_cluster_ready "core01"
