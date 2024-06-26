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

# shellcheck source=./scripts/_utils.sh
source _utils.sh

sudo rm -r /tmp/*
for step in install configure; do
    info "Running $step process"
    bash "./$step.sh"
    [[ ${ENABLE_FUNC_TEST:-false} != "true" && -f "./${step}_test.sh" ]] || bash "./${step}_test.sh"
done
