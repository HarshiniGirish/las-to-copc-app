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

read_bool() {
  case "${1,,}" in
    true|1|yes|on) return 0 ;;
    false|0|no|off|"") return 1 ;;
    *) echo "Invalid boolean: $1" >&2; exit 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input_dir)        INPUT_DIR="$2"; shift 2 ;;
    --site)             SITE="$2"; shift 2 ;;
    --tile_size)        TILE_SIZE="$2"; shift 2 ;;
    --voxel_size)
      VOXEL_SIZE="$2"
      [[ -z "${VOXEL_SIZE}" || "${VOXEL_SIZE}" == "null" ]] && VOXEL_SIZE=""
      shift 2
      ;;
    --keep_extra_dims)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        read_bool "$2" && KEEP_EXTRA_DIMS=1 || KEEP_EXTRA_DIMS=0
        shift 2
      else
        KEEP_EXTRA_DIMS=1; shift
      fi
      ;;
    --merge)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        read_bool "$2" && MERGE=1 || MERGE=0
        shift 2
      else
        MERGE=1; shift
      fi
      ;;
    --overwrite)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        read_bool "$2" && OVERWRITE=1 || OVERWRITE=0
        shift 2
      else
        OVERWRITE=1; shift
      fi
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${INPUT_DIR}" || -z "${SITE}" ]]; then
  echo "Required: --input_dir <path> --site <string>" >&2
  exit 1
fi

OUTDIR="${PWD}/output"
mkdir -p "${OUTDIR}"

CMD=(
  Rscript "${basedir}/las_to_copc_tiled.R"
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
