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

download_href() {
  local href="$1"
  local dest="$2"
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
        cp "${href}" "${dest}"
      else
        echo "Local href missing: ${href}" >&2
        return 1
      fi
      ;;
    *)
      echo "Unrecognized href: ${href}" >&2
      return 1
      ;;
  esac
}

# Fetch first lidar asset href from a STAC Item HTTPS URL (or local item JSON).
stac_item_asset_href() {
  local item_url="$1"
  python3 - "${item_url}" <<'PY'
import json, sys, urllib.request

url = sys.argv[1]
if url.startswith("http://") or url.startswith("https://"):
    with urllib.request.urlopen(url, timeout=60) as resp:
        item = json.load(resp)
else:
    with open(url, "r", encoding="utf-8") as f:
        item = json.load(f)

assets = item.get("assets") or {}
# Prefer common lidar asset keys, then any .las/.laz href
preferred_keys = ("data", "laz", "las", "copc", "pointcloud", "point_cloud")
candidates = []
for key in preferred_keys:
    a = assets.get(key)
    if isinstance(a, dict) and a.get("href"):
        candidates.append(a["href"])
for a in assets.values():
    if isinstance(a, dict) and a.get("href"):
        href = a["href"]
        if href.lower().endswith((".las", ".laz", ".copc.laz")):
            candidates.append(href)
if not candidates:
    for a in assets.values():
        if isinstance(a, dict) and a.get("href"):
            candidates.append(a["href"])
            break
if not candidates:
    raise SystemExit("No assets.href found in STAC Item")
print(candidates[0])
PY
}

find_laz_under() {
  local root="$1"
  find "${root}" -type f \( -iname '*.las' -o -iname '*.laz' \) 2>/dev/null | head -n 1 || true
}

extract_href_from_json_tree() {
  local root="$1"
  python3 - "${root}" <<'PY' 2>/dev/null || true
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

prefer = [h for h in hrefs if h.lower().endswith((".las", ".laz", ".copc.laz"))]
ordered = prefer + [h for h in hrefs if h not in prefer]
if ordered:
    print(ordered[0])
PY
}

# Resolve to a local .las/.laz for R. Accepts:
# - local file/dir (MAAP Directory stage-in)
# - STAC Item https://.../items/...
# - s3://...laz
# - broken staged path: search parent / download from embedded STAC hrefs
resolve_lidar_input() {
  local path="$1"
  local found=""
  local href=""
  local dest=""
  local parent=""
  local stage_dir="${PWD}/staged_input"
  mkdir -p "${stage_dir}"
  dest="${stage_dir}/input.laz"

  # Direct remote URLs (preferred after re-registering input as string)
  if [[ "${path}" == s3://* ]]; then
    echo "Downloading ${path}" >&2
    download_href "${path}" "${dest}"
    echo "${dest}"
    return 0
  fi

  if [[ "${path}" == https://stac.maap-project.org/* ]] || [[ "${path}" == http://stac.maap-project.org/* ]] \
     || [[ "${path}" == */collections/*/items/* ]]; then
    echo "Fetching STAC Item: ${path}" >&2
    href=$(stac_item_asset_href "${path}")
    echo "STAC asset href: ${href}" >&2
    download_href "${href}" "${dest}"
    echo "${dest}"
    return 0
  fi

  if [[ -f "${path}" ]]; then
    case "${path,,}" in
      *.las|*.laz|*.json)
        if [[ "${path,,}" == *.json ]]; then
          href=$(stac_item_asset_href "${path}")
          echo "STAC asset href: ${href}" >&2
          download_href "${href}" "${dest}"
          echo "${dest}"
          return 0
        fi
        echo "${path}"
        return 0
        ;;
    esac
  fi

  if [[ -d "${path}" ]]; then
    found=$(find_laz_under "${path}")
    if [[ -n "${found}" ]]; then
      echo "${found}"
      return 0
    fi
    echo "Staged directory contents of ${path}:" >&2
    find "${path}" -maxdepth 3 -type f 2>/dev/null | head -n 50 >&2 || true
    href=$(extract_href_from_json_tree "${path}")
    if [[ -n "${href}" ]]; then
      echo "Resolved STAC asset href: ${href}" >&2
      if [[ "${href}" == /* && -f "${href}" ]]; then
        echo "${href}"
        return 0
      fi
      if [[ "${href}" != /* && -f "${path}/${href}" ]]; then
        echo "${path}/${href}"
        return 0
      fi
      download_href "${href}" "${dest}"
      echo "${dest}"
      return 0
    fi
    echo "No .las/.laz and no STAC asset href under ${path}" >&2
    return 1
  fi

  # CWL sometimes passes a staged path that was never created. Search parent.
  parent=$(dirname "${path}")
  if [[ -d "${parent}" ]]; then
    echo "Path missing (${path}); searching parent ${parent}" >&2
    find "${parent}" -maxdepth 4 -type f 2>/dev/null | head -n 50 >&2 || true
    found=$(find_laz_under "${parent}")
    if [[ -n "${found}" ]]; then
      echo "${found}"
      return 0
    fi
    href=$(extract_href_from_json_tree "${parent}")
    if [[ -n "${href}" ]]; then
      echo "Resolved STAC asset href from parent: ${href}" >&2
      download_href "${href}" "${dest}"
      echo "${dest}"
      return 0
    fi
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

SITE="${SITE#"${SITE%%[![:space:]]*}"}"
SITE="${SITE%"${SITE##*[![:space:]]}"}"
INPUT_DIR="${INPUT_DIR#"${INPUT_DIR%%[![:space:]]*}"}"
INPUT_DIR="${INPUT_DIR%"${INPUT_DIR##*[![:space:]]}"}"

if [[ -z "${INPUT_DIR}" || -z "${SITE}" ]]; then
  echo "Required: --input_dir <path-or-url> --site <string>" >&2
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
