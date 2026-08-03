#!/usr/bin/env bash
set -euo pipefail

basedir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

INPUT_DIR=""
SITE=""
TILE_SIZE="250"
VOXEL_SIZE=""
KEEP_EXTRA_DIMS=0
MERGE=0
OVERWRITE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input_dir)        INPUT_DIR="$2"; shift 2 ;;
    --site)             SITE="$2"; shift 2 ;;
    --tile_size)        TILE_SIZE="$2"; shift 2 ;;
    --voxel_size)       VOXEL_SIZE="$2"; shift 2 ;;
    --keep_extra_dims)  KEEP_EXTRA_DIMS=1; shift ;;
    --merge)            MERGE=1; shift ;;
    --overwrite)        OVERWRITE=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${INPUT_DIR}" || -z "${SITE}" ]]; then
  echo "Required: --input_dir <Directory> --site <string>" >&2
  exit 1
fi

OUTDIR="${PWD}/output"
mkdir -p "${OUTDIR}"

CMD=(
  python "${basedir}/las_to_copc_tiled.py"
  --input "${INPUT_DIR}"
  --output "${OUTDIR}"
  --site "${SITE}"
  --tile-size "${TILE_SIZE}"
)

if [[ -n "${VOXEL_SIZE}" ]]; then
  CMD+=(--voxel-size "${VOXEL_SIZE}")
fi
[[ "${KEEP_EXTRA_DIMS}" -eq 1 ]] && CMD+=(--keep-extra-dims)
[[ "${MERGE}" -eq 1 ]] && CMD+=(--merge)
[[ "${OVERWRITE}" -eq 1 ]] && CMD+=(--overwrite)

echo "Running: conda run -n copc ${CMD[*]}"
exec conda run --live-stream --name copc "${CMD[@]}"
