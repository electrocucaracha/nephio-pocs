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

# shellcheck source=./scripts/_assertions.sh
source _assertions.sh

gitea_cache_tokens_base_dir=/tmp
gitea_admin_account=nephio
nephio_repos=(mgmt mgmt-staging)

function _assert_inotify_maxs {
    local var="$1"
    local val="$2"

    assert_contains "$(sudo sysctl sysctl --all | grep 'fs.inotify')" "fs.inotify.max_user_$var"
    assert_are_equal "$(sudo sysctl sysctl --values "fs.inotify.max_user_$var" 2>/dev/null)" "$val"
}

function exec_gitea {
    gitea_cmd="/app/gitea/gitea $*"
    kubectl exec -n gitea -c gitea --context kind-gitea "$(kubectl get pods -n gitea -l app=gitea --context kind-gitea -o jsonpath='{.items[*].metadata.name}')" -- su git -c "$gitea_cmd"
}

function _get_admin_token {
    if [ ! -f "$gitea_cache_tokens_base_dir/$gitea_admin_account" ]; then
        mkdir -p "$gitea_cache_tokens_base_dir"
        token="$(exec_gitea admin user generate-access-token --username "$gitea_admin_account" --scopes write:org,admin:org | grep 'Access token' | awk -F ':' '{ print $2}')"
        echo "$token" | xargs | tee "$gitea_cache_tokens_base_dir/$gitea_admin_account"
    else
        cat "$gitea_cache_tokens_base_dir/$gitea_admin_account"
    fi
}

function curl_gitea_api {
    curl_cmd="curl -s -H 'Authorization: token $(_get_admin_token)' -H 'content-type: application/json' http://$(kubectl get service gitea -n gitea --context kind-gitea -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000/api/v1/$1"
    [[ -z ${2-} ]] || curl_cmd+=" -k --data '$2'"
    eval "$curl_cmd"
}

# shellcheck disable=SC1091
[ -f /etc/profile.d/path.sh ] && source /etc/profile.d/path.sh

info "Assert inotify user max values"
_assert_inotify_maxs "watches" "524288"
_assert_inotify_maxs "instances" "512"

info "Assert KinD clusters creation"
assert_are_equal "$(sudo docker ps --filter label=io.x-k8s.kind.role=control-plane --quiet | wc -l)" "2" "There are two KinD clusters running"

info "Assert gitea users creation"
assert_contains "$(exec_gitea admin user list --admin)" "$gitea_admin_account"

info "Assert repositories creation"
nephio_gitea_repos="$(curl_gitea_api "users/nephio/repos")"
for repo in "${nephio_repos[@]}"; do
    assert_contains "$nephio_gitea_repos" "$repo"
done
