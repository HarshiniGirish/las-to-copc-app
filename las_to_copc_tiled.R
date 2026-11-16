#!/usr/bin/env Rscript
# Convert raw LAS/LAZ files to tiled COPC using lasR.
#
# Mirrors geotrees_meeting_2026/las_to_copc_tiled.py (MAAP-Project/geotrees-demo
# @ 4f9de9a2): optional voxel thinning, fixed-size tiles, outputs named
# {site}_{Xmin}_{Ymin}.copc.laz.
#
# Install lasR (not on CRAN):
#   install.packages(
#     "lasR",
#     repos = c("https://r-lidar.r-universe.dev", "https://cloud.r-project.org")
#   )
#
# Example:
#   Rscript las_to_copc_tiled.R \
#     --input 01_raw/file.laz \
#     --output ./02_input \
#     --site MYSITE

suppressPackageStartupMessages({
  library(optparse)
  library(lasR)
})

# Core LAS attributes retained when --keep-extra-dims is not set.
CORE_ATTRIBUTES <- c(
  "X", "Y", "Z", "Intensity", "gpstime", "ReturnNumber", "NumberOfReturns",
  "ScanDirectionFlag", "EdgeOfFlightLine", "Classification", "ScanAngle",
  "UserData", "PointSourceID", "R", "G", "B", "NIR"
)

discover_inputs <- function(input_path) {
  if (length(input_path) != 1L || is.na(input_path) || !nzchar(input_path)) {
    stop("No LAS/LAZ inputs found at: ", input_path)
  }
  input_path <- trimws(input_path)
  if (dir.exists(input_path)) {
    # Recursive: MAAP STAC stage-in may nest assets under the Directory
    files <- sort(list.files(
      input_path,
      pattern = "(?i)\\.(las|laz)$",
      full.names = TRUE,
      recursive = TRUE
    ))
    if (length(files) == 0L) {
      listing <- list.files(input_path, full.names = TRUE, recursive = TRUE)
      stop(
        "No LAS/LAZ inputs found at: ", input_path,
        "\nDirectory listing (", length(listing), " entries):\n",
        paste(utils::head(listing, 40L), collapse = "\n")
      )
    }
  } else if (file.exists(input_path)) {
    files <- normalizePath(input_path, winslash = "/", mustWork = TRUE)
  } else {
    files <- sort(Sys.glob(input_path))
  }
  if (length(files) == 0L) {
    stop("No LAS/LAZ inputs found at: ", input_path)
  }
  files
}

read_las_bbox <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  seek(con, 187L)
  vals <- readBin(con, what = "double", n = 6L, size = 8L, endian = "little")
  list(xmin = vals[1], xmax = vals[2], ymin = vals[3], ymax = vals[4])
}

tile_name <- function(site, xmin, ymin) {
  sprintf("%s_%d_%d.copc.laz", site, as.integer(xmin), as.integer(ymin))
}

build_pipeline <- function(out_template, voxel_size, keep_extra_dims) {
  stages <- reader()
  if (!isTRUE(keep_extra_dims)) {
    stages <- stages + keep_attributes(CORE_ATTRIBUTES)
  }
  if (!is.null(voxel_size) && is.finite(voxel_size) && voxel_size > 0) {
    stages <- stages + sampling_voxel(res = voxel_size)
  }
  stages + write_copc(ofile = out_template)
}

rename_tiles <- function(written, out_dir, site, tile_size, overwrite) {
  if (is.null(written) || length(written) == 0L) {
    return(invisible(character()))
  }
  written <- unique(as.character(unlist(written, use.names = FALSE)))
  written <- written[file.exists(written)]
  renamed <- character()

  for (src in written) {
    bb <- read_las_bbox(src)
    xmin <- as.integer(floor(bb$xmin / tile_size) * tile_size)
    ymin <- as.integer(floor(bb$ymin / tile_size) * tile_size)
    dest <- file.path(out_dir, tile_name(site, xmin, ymin))

    if (normalizePath(src, winslash = "/", mustWork = FALSE) ==
        normalizePath(dest, winslash = "/", mustWork = FALSE)) {
      message("  wrote: ", basename(dest))
      renamed <- c(renamed, dest)
      next
    }

    if (file.exists(dest) && !isTRUE(overwrite)) {
      message("  skip (exists): ", basename(dest))
      if (!identical(src, dest) && file.exists(src)) {
        unlink(src)
      }
      next
    }

    if (file.exists(dest) && isTRUE(overwrite)) {
      unlink(dest)
    }
    ok <- file.rename(src, dest)
    if (!isTRUE(ok)) {
      # Cross-device rename fallback
      if (!file.copy(src, dest, overwrite = TRUE)) {
        stop("Failed to move ", src, " -> ", dest)
      }
      unlink(src)
    }
    message("  wrote: ", basename(dest))
    renamed <- c(renamed, dest)
  }
  invisible(renamed)
}

run_conversion <- function(inputs, out_dir, site, tile_size, voxel_size,
                           keep_extra_dims, merge, overwrite) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  # Temporary wildcard pattern; files are renamed to {site}_{Xmin}_{Ymin}.copc.laz
  out_template <- file.path(out_dir, paste0(site, "_*.copc.laz"))
  pipeline <- build_pipeline(out_template, voxel_size, keep_extra_dims)

  process_one <- function(files) {
    # Skip if every expected tile already exists and overwrite is false:
    # lasR still runs; rename_tiles honors --overwrite / skip.
    message("Processing ", length(files), " file(s) with chunk=", tile_size)
    ans <- exec(
      pipeline,
      on = files,
      with = list(chunk = tile_size, progress = TRUE)
    )
    written <- NULL
    if (is.list(ans) && !is.null(ans$write_copc)) {
      written <- ans$write_copc
    } else if (is.list(ans) && !is.null(ans$write_las)) {
      written <- ans$write_las
    } else if (is.character(ans)) {
      written <- ans
    } else {
      written <- list.files(
        out_dir,
        pattern = paste0("^", gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", site), "_.*\\.copc\\.laz$"),
        full.names = TRUE
      )
    }
    rename_tiles(written, out_dir, site, tile_size, overwrite)
  }

  if (isTRUE(merge) || length(inputs) == 1L) {
    process_one(inputs)
  } else {
    for (f in inputs) {
      message("Processing: ", basename(f))
      tryCatch(
        process_one(f),
        error = function(e) {
          message("  FAILED: ", f, "\n  ", conditionMessage(e))
        }
      )
    }
  }
}

main <- function() {
  option_list <- list(
    make_option("--input", type = "character", default = "01_raw",
                help = "Input file, directory, or glob [default: %default]"),
    make_option("--output", type = "character", default = "02_input",
                help = "Output directory [default: %default]"),
    make_option("--site", type = "character", default = NULL,
                help = "Site code prefix for filenames"),
    make_option("--tile-size", type = "double", default = 250,
                dest = "tile_size",
                help = "Tile edge length in CRS units [default: %default]"),
    make_option("--voxel-size", type = "double", default = NA,
                dest = "voxel_size",
                help = "Optional voxel thinning cell size in CRS units"),
    make_option("--keep-extra-dims", action = "store_true", default = FALSE,
                dest = "keep_extra_dims",
                help = "Preserve provider ExtraBytes attributes"),
    make_option("--merge", action = "store_true", default = FALSE,
                help = "Merge all inputs before tiling"),
    make_option("--overwrite", action = "store_true", default = FALSE,
                help = "Overwrite existing output tiles")
  )

  parser <- OptionParser(
    option_list = option_list,
    description = "Convert raw LAS/LAZ to tiled COPC with lasR."
  )
  opt <- parse_args(parser)

  if (is.null(opt$site) || !nzchar(trimws(opt$site))) {
    print_help(parser)
    stop("--site is required", call. = FALSE)
  }
  opt$site <- trimws(opt$site)

  inputs <- discover_inputs(opt$input)
  voxel_size <- if (is.na(opt$voxel_size)) NULL else opt$voxel_size

  message("lasR version : ", as.character(utils::packageVersion("lasR")))
  message("Found ", length(inputs), " input file(s).")
  message("Site         : ", opt$site)
  message("Tile size    : ", opt$tile_size)
  message("Voxel filter : ", if (is.null(voxel_size)) "off" else voxel_size)
  message("Extra dims   : ", if (isTRUE(opt$keep_extra_dims)) "kept" else "dropped")
  message("Merge        : ", isTRUE(opt$merge))
  message("Output dir   : ", normalizePath(opt$output, winslash = "/", mustWork = FALSE))
  message("")

  run_conversion(
    inputs = inputs,
    out_dir = opt$output,
    site = opt$site,
    tile_size = opt$tile_size,
    voxel_size = voxel_size,
    keep_extra_dims = isTRUE(opt$keep_extra_dims),
    merge = isTRUE(opt$merge),
    overwrite = isTRUE(opt$overwrite)
  )

  message("Done.")
  invisible(0L)
}

status <- tryCatch(
  {
    main()
    0L
  },
  error = function(e) {
    message("ERROR: ", conditionMessage(e))
    1L
  }
)
quit(save = "no", status = status)
