#!/usr/bin/env bash
set -euo pipefail
chmod +x run.sh
docker build -t las-to-copc:local .
