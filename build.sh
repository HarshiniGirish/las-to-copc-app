#!/usr/bin/env bash
set -euo pipefail

basedir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
chmod +x "${basedir}/run.sh"

conda=${CONDA_EXE:-conda}

# Create or update the env from environment.yaml
if conda env list | awk '{print $1}' | grep -qx copc; then
  PIP_REQUIRE_VENV=0 "${conda}" env update --quiet --prune --solver libmamba \
    --name copc --file "${basedir}/environment.yaml"
else
  PIP_REQUIRE_VENV=0 "${conda}" env create --quiet --solver libmamba \
    --file "${basedir}/environment.yaml"
fi
