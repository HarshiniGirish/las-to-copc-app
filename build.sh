#!/usr/bin/env bash
set -euo pipefail

basedir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
chmod +x "${basedir}/run.sh" "${basedir}/las_to_copc_tiled.R"

conda=${CONDA_EXE:-conda}

# Create or update the env from environment.yaml
if conda env list | awk '{print $1}' | grep -qx copc; then
  PIP_REQUIRE_VENV=0 "${conda}" env update --quiet --prune --solver libmamba \
    --name copc --file "${basedir}/environment.yaml"
else
  PIP_REQUIRE_VENV=0 "${conda}" env create --quiet --solver libmamba \
    --file "${basedir}/environment.yaml"
fi

# lasR is hosted on r-universe (not CRAN)
"${conda}" run --name copc Rscript -e \
  "install.packages('lasR', repos = c('https://r-lidar.r-universe.dev', 'https://cloud.r-project.org'))"
