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

# shellcheck source=./scripts/_utils.sh
source _utils.sh

function _assert_cmd_exists {
    local cmd="$1"
    local error_msg="${2:-"$cmd command doesn't exist"}"

    [[ ${DEBUG:-false} != "true" ]] || debug "Command $cmd assertion validation"
    command -v "$cmd" >/dev/null || error "$error_msg"
}

info "Assert command requirements"
for cmd in docker kubectl kpt kind; do
    _assert_cmd_exists "$cmd"
done
