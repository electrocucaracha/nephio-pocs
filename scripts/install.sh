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
if [[ ${DEBUG:-false} == "true" ]]; then
    set -o xtrace
    export PKG_DEBUG=true
fi

# shellcheck source=./scripts/_utils.sh
source _utils.sh
# shellcheck source=./scripts/defaults.env
source defaults.env

export PKG_KREW_PLUGINS_LIST=" "
export PKG_CNI_PLUGINS_FOLDER="/opt/cni/bin/"

# Install dependencies
# NOTE: Shorten link -> https://github.com/electrocucaracha/pkg-mgr_scripts
curl -fsSL http://bit.ly/install_pkg | PKG_COMMANDS_LIST="docker,kubectl,kind" PKG="cni-plugins" bash

if ! command -v kpt >/dev/null; then
    curl -s "https://i.jpillora.com/GoogleContainerTools/kpt@v${KPT_VERSION}!" | bash
    kpt completion bash | sudo tee /etc/bash_completion.d/kpt >/dev/null
fi
