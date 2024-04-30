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

function _assert_inotify_maxs {
    local var="$1"
    local val="$2"

    assert_contains "$(sudo sysctl sysctl --all | grep 'fs.inotify')" "fs.inotify.max_user_$var"
    assert_are_equal "$(sudo sysctl sysctl --values "fs.inotify.max_user_$var" 2>/dev/null)" "$val"
}

# shellcheck disable=SC1091
[ -f /etc/profile.d/path.sh ] && source /etc/profile.d/path.sh

info "Assert inotify user max values"
_assert_inotify_maxs "watches" "524288"
_assert_inotify_maxs "instances" "512"

info "Assert KinD clusters creation"
assert_are_equal "$(sudo docker ps --filter label=io.x-k8s.kind.role=control-plane --quiet | wc -l)" "2" "There are two KinD clusters running"
