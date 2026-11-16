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

On MAAP, pass a **STAC Item URL** for `input_dir` (Directory), e.g.:

```text
https://stac.maap-project.org/collections/GEDI_CalVal_Lidar_Data_Compressed/items/usa_moscowmtn_MM03_1401
```

`run.sh` resolves the staged folder, and if the asset is still `s3://` (cwltool does not fetch S3), downloads it with `aws s3 cp` before calling R.

## MAAP register / build

| Field | Value |
|-------|--------|
| Repository | `https://github.com/HarshiniGirish/las-to-copc-app` |
| Branch | `main` |
| Build command | `las-to-copc-app/build.sh` |
| Run command | `las-to-copc-app/run.sh` |

`build.sh` creates the `copc` conda env and installs `lasR` from r-universe. Job results are written under `./output`.
