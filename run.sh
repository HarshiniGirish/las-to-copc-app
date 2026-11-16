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

# MAAP Directory stage-in often yields a folder with catalog.json / item JSON and
# asset hrefs that are still s3:// (cwltool does not fetch s3). Resolve to a
# local .las/.laz path for the R script.
resolve_lidar_input() {
  local path="$1"
  local found=""
  local href=""
  local dest=""

  if [[ -f "${path}" ]]; then
    case "${path,,}" in
      *.las|*.laz) echo "${path}"; return 0 ;;
    esac
  fi

  if [[ -d "${path}" ]]; then
    found=$(find "${path}" -type f \( -iname '*.las' -o -iname '*.laz' \) 2>/dev/null | head -n 1 || true)
    if [[ -n "${found}" ]]; then
      echo "${found}"
      return 0
    fi

    echo "Staged directory contents of ${path}:" >&2
    find "${path}" -maxdepth 3 -type f 2>/dev/null | head -n 50 >&2 || true

    # Prefer hrefs from STAC JSON (local file:// or relative, or s3:// / https://)
    href=$(python3 - "${path}" <<'PY' 2>/dev/null || true
import json, os, sys
root = sys.argv[1]
hrefs = []

def walk(obj):
    if isinstance(obj, dict):
        if "href" in obj and isinstance(obj["href"], str):
            hrefs.append(obj["href"])
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for v in obj:
            walk(v)

for dirpath, _, files in os.walk(root):
    for name in files:
        if not name.endswith(".json"):
            continue
        p = os.path.join(dirpath, name)
        try:
            with open(p, "r", encoding="utf-8") as f:
                walk(json.load(f))
        except Exception:
            pass

# Prefer lidar-looking hrefs
prefer = [h for h in hrefs if h.lower().endswith((".las", ".laz", ".copc.laz"))]
ordered = prefer + [h for h in hrefs if h not in prefer]
for h in ordered:
    print(h)
    break
PY
)
    if [[ -z "${href}" ]]; then
      echo "No .las/.laz and no STAC asset href under ${path}" >&2
      return 1
    fi

    echo "Resolved STAC asset href: ${href}" >&2
    dest="${path}/staged_input.laz"

    case "${href}" in
      s3://*)
        aws s3 cp "${href}" "${dest}"
        ;;
      https://*|http://*)
        curl -fsSL -o "${dest}" "${href}"
        ;;
      file://*)
        cp "${href#file://}" "${dest}"
        ;;
      /*)
        if [[ -f "${href}" ]]; then
          echo "${href}"
          return 0
        fi
        echo "Local href missing: ${href}" >&2
        return 1
        ;;
      *)
        # Relative to the staged directory
        if [[ -f "${path}/${href}" ]]; then
          echo "${path}/${href}"
          return 0
        fi
        echo "Unrecognized href: ${href}" >&2
        return 1
        ;;
    esac

    if [[ ! -f "${dest}" ]]; then
      echo "Failed to stage lidar asset to ${dest}" >&2
      return 1
    fi
    echo "${dest}"
    return 0
  fi

  echo "Input path not found: ${path}" >&2
  return 1
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

# Trim whitespace from site (CWL sometimes passes " MM03")
SITE="${SITE#"${SITE%%[![:space:]]*}"}"
SITE="${SITE%"${SITE##*[![:space:]]}"}"

if [[ -z "${INPUT_DIR}" || -z "${SITE}" ]]; then
  echo "Required: --input_dir <path> --site <string>" >&2
  exit 1
fi

RESOLVED_INPUT=$(resolve_lidar_input "${INPUT_DIR}")
echo "Using lidar input: ${RESOLVED_INPUT}"

OUTDIR="${PWD}/output"
mkdir -p "${OUTDIR}"

CMD=(
  Rscript "${basedir}/las_to_copc_tiled.R"
  --input "${RESOLVED_INPUT}"
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
