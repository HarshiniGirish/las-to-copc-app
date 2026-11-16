# las-to-copc-app

MAAP OGC Application Package that converts raw LAS/LAZ lidar to tiled Cloud-Optimized Point Cloud (COPC) files using **R** and [**lasR**](https://r-lidar.github.io/lasR/).

Based on the geotrees workflow in [MAAP-Project/geotrees-demo#11](https://github.com/MAAP-Project/geotrees-demo/pull/11).

## Local run

```bash
conda env create -f environment.yaml
conda activate copc
Rscript -e "install.packages('lasR', repos = c('https://r-lidar.r-universe.dev', 'https://cloud.r-project.org'))"

Rscript las_to_copc_tiled.R \
  --input 01_raw/file.laz \
  --output ./02_input \
  --site MYSITE \
  --tile-size 250
```

Inputs should be in a **projected meter CRS**. Outputs are named `{site}_{Xmin}_{Ymin}.copc.laz`.

On MAAP, register `input_dir` as type **string** and pass a **STAC Item URL** or **`s3://...laz`**:

```text
https://stac.maap-project.org/collections/GEDI_CalVal_Lidar_Data_Compressed/items/usa_moscowmtn_MM03_1401
```

`run.sh` downloads the asset itself (`aws s3 cp` / curl). Do not rely on CWL Directory stage-in for S3 lidar — it often leaves an empty path.

## MAAP register / build

| Field | Value |
|-------|--------|
| Repository | `https://github.com/HarshiniGirish/las-to-copc-app` |
| Branch | `main` |
| Build command | `las-to-copc-app/build.sh` |
| Run command | `las-to-copc-app/run.sh` |

`build.sh` creates the `copc` conda env and installs `lasR` from r-universe. Job results are written under `./output`.
