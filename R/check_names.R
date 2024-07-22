#' Check file names
#'
#' Checks the file names according to [ADV standard](https://www.adv-online.de/AdV-Produkte/Standards-und-Produktblaetter/Standards-der-Geotopographie/binarywriterservlet?imgUid=6b510f6e-a708-d081-505a-20954cd298e1&uBasVariant=11111111-1111-1111-1111-111111111111).
#' File names should be in the following schema:
#' `prefix`_`utmzone`_`minx`_`miny`_`tilesize`_`region`_`year``.laz`
#'
#' (e.g. `3dm_32_547_5724_1_ni_2024.laz`)
#'
#' @param path A path to a directory which contains las/laz files
#' @param prefix 3 letter character. Naming prefix (defaults to "3dm")
#' @param zone 2 digits integer. UTM zone (defaults to 32)
#' @param region 2 letter character. (optional) federal state abbreviation. It will be fetched automatically if Null.
#' @param year YYYY. (optional) acquisition year to append to filename.
#' If not provided the year will be extracted from the files. It will be the acquisition date if points contain datetime in GPStime format, otherwise it will get the year from the file header, which is the processing date by definition.
#' @param full.names Whether to return the full file path or just the file names (default)
#'
#' @return A dataframe with name_is, name_should, correct
#' @export
#'
#' @examples
#' f <- system.file("extdata", package = "managelidar")
#' check_names(f)
check_names <- function(path, prefix = "3dm", zone = 32, region = NULL, year = NULL, full.names = FALSE) {
  print("create VPC with GPStime")
  ans <- lasR::exec(
    lasR::set_crs(25832) + lasR::write_vpc(ofile = tempfile(fileext = ".vpc"), use_gpstime = TRUE, absolute_path = TRUE),
    with = list(ncores = lasR::concurrent_files(lasR::half_cores())),
    on = path
  )

  json <- jsonlite::fromJSON(ans)


  bbox <- json$features$properties$`proj:bbox`

  minx <- sapply(bbox, function(x) floor(round(x[1] / 1000, 2)))
  miny <- sapply(bbox, function(x) floor(round(x[2] / 1000, 2)))
  maxx <- sapply(bbox, function(x) floor(round(x[3] / 1000, 2)))
  maxy <- sapply(bbox, function(x) floor(round(x[4] / 1000, 2)))

# get tilesize from larger extent (x,y) and take into account small inaccuracies
  tilesize_x <- maxx - minx
  tilesize_y <- maxy - miny

  tilesize <- ceiling(pmax(tilesize_x, tilesize_y) - 0.05)


  if (is.null(region)) {
# get region
  state_codes <- c(
    "Baden-Württemberg" = "bw",
    "Bayern" = "by",
    "Berlin" = "be",
    "Brandenburg" = "bb",
    "Bremen" = "hb",
    "Hamburg" = "hh",
    "Hessen" = "he",
    "Mecklenburg-Vorpommern" = "mv",
    "Niedersachsen" = "ni",
    "Nordrhein-Westfalen" = "nw",
    "Rheinland-Pfalz" = "rp",
    "Saarland" = "sl",
    "Sachsen" = "sn",
    "Sachsen-Anhalt" = "st",
    "Schleswig-Holstein" = "sh",
    "Thüringen" = "th"
  )

  url <- "https://public.opendatasoft.com/api/explore/v2.1/catalog/datasets/georef-germany-land/exports/parquet?lang=en&timezone=Europe%2FBerlin"
  states_sf <- arrow::read_parquet(file = url)|>
    sf::st_as_sf() |>
    sf::st_set_geometry('geo_shape') |>
    dplyr::mutate(code = state_codes[lan_name]) |>
    sf::st_set_crs(4326)

  extents <- json$features$bbox

  find_state_code <- function(bbox_coords, states_sf) {
    bbox <- sf::st_as_sfc(sf::st_bbox(c(xmin = bbox_coords[1], ymin = bbox_coords[2], xmax = bbox_coords[3], ymax = bbox_coords[4]), crs = 4326))

    sf::st_agr(states_sf) = "constant"
    intersections <- sf::st_intersection(states_sf, bbox)
    intersections <- intersections |>  dplyr::mutate(intersection_area = sf::st_area(geo_shape))

    state_code <- intersections |>
      dplyr::filter(intersection_area == max(intersection_area)) |>
      dplyr::pull(code)  # Assuming your state code column is named `state_code`

    return(state_code)
  }

  # Apply the function to each bbox
  region <- sapply(extents, find_state_code, states_sf = states_sf)

  }



  if (is.null(year)) {
    # set year to acqusition /processing year
    year <- format(as.Date(json$features$properties$datetime), "%Y")
  }

  if (full.names == FALSE) {
    name_is <- basename(json$features$assets$data$href)
    name_should <- paste0(prefix, "_", zone, "_", minx, "_", miny, "_", tilesize, "_", region, "_", year, ".", tools::file_ext(json$features$assets$data$href))
  } else {
    name_is <- json$features$assets$data$href
    name_should <- file.path(dirname(name_is), paste0(prefix, "_", zone, "_", minx, "_", miny, "_", tilesize, "_", region, "_", year, ".", tools::file_ext(json$features$assets$data$href)))
  }


  dat <- data.frame(
    name_is = name_is,
    name_should = name_should,
    correct = name_is == name_should
  )

  return(dat)
}