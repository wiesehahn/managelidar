#' Get data in a standardized format and structure
#'
#' This function copies data from one folder to another folder, while ensuring certain data formating and folder structure. CRS is set, points are sorted, files are compressed, files are renamed according to [ADV standard](https://www.adv-online.de/AdV-Produkte/Standards-und-Produktblaetter/Standards-der-Geotopographie/binarywriterservlet?imgUid=6b510f6e-a708-d081-505a-20954cd298e1&uBasVariant=11111111-1111-1111-1111-111111111111), files are ordered in folders by acquisition date and campaign, a VPC is created and files are spatially indexed as COPC.
#'
#' @param origin path. The path to a directory which contains las/laz files
#' @param destination path. The directory under which the processed files are copied and subfolders (year/campaign) are created
#' @param campaign character. Name of the project or campaign of data acquisition.
#' @param origin_recurse boolean. Should files in subfolder be included?
#' @param prefix 3 letter character. Naming prefix (defaults to "3dm")
#' @param zone 2 digits integer. UTM zone (defaults to 32)
#' @param region 2 letter character. (optional) federal state abbreviation. It will be fetched automatically if not defined (default).
#' @param year YYYY. (optional) acquisition year to append to filename.
#' If not provided (default) the year will be extracted from the files. It will be the acquisition date if points contain datetime in GPStime format, otherwise it will get the year from the file header, which is the processing date by definition.
#'
#' @return A structured copy of input lidar data
#' @export
#'
#' @examples
#' \dontrun{
#' f <- system.file("extdata", package = "managelidar")
#' get_data(f, tempdir(), "landesbefliegung")
#' }
get_data <- function(origin, destination, campaign, origin_recurse = FALSE, prefix = "3dm", zone = 32, region = NULL, year = NULL, verbose = FALSE) {
  # create temporary folder
  tmpfolder <- fs::dir_create(fs::path(destination, "in_process"), recurse = TRUE)
  # create documentary folder
  docufolder <- fs::dir_create(fs::path(destination, "doku"), recurse = TRUE)


  # just in case process stopped
  processed_files <- list.files(tmpfolder, pattern = "/*.laz$")
  all_files <- list.files(origin, pattern = "/*.las|z$", full.names = TRUE, recursive = origin_recurse)
  unprocessed_files <- setdiff(
    fs::path_ext_remove(fs::path_ext_remove(fs::path_file(all_files))),
    fs::path_ext_remove(fs::path_ext_remove(fs::path_file(processed_files)))
  )
  unprocessed_files <- all_files[fs::path_ext_remove(fs::path_ext_remove(fs::path_file(all_files))) %in% unprocessed_files]

  if (verbose) {
    print(paste0("Writing ", length(unprocessed_files), " files to tempfolder (", tmpfolder, "). (save as COPC, define CRS as EPSG:25832, sort points spatially)"))
  }

  lasR::exec(
    # set CRS (for the case it is not correctly set)
    lasR::set_crs(25832) +
      # sort points for better compression and efficient reading
      lasR::sort_points() +
      # write compressed
      lasR::write_copc(
        ofile = paste0(tmpfolder, "/*.copc.laz"),
        density = "normal"
      ),
    with = list(ncores = lasR::concurrent_files(lasR::half_cores()), progress = TRUE),
    on = unprocessed_files
  )

  # rename files according to ADV standard
  if (verbose) {
    print("Rename files according to ADV standard")
  }

  managelidar::set_names(path = tmpfolder, prefix, zone, region, year, copc = TRUE, verbose)

  if (verbose) {
    print(paste0("Move files to destination folder (", destination, "), sorting them in subfolders by year and campaign. Also creating Virtual Point Clouds for each subfolder"))
  }


  now <- as.integer(format(Sys.time(), "%Y"))
  for (year in c(2000:now)) {
    files_to_move <- list.files(path = tmpfolder, pattern = paste0("*", year, ".copc.laz$"), full.names = TRUE)

    if (length(files_to_move) > 0) {
      # sort files in folders by year
      destination_dir <- fs::path(destination, year, campaign)

      if (verbose) {
        print(paste0("Move files to: ", destination_dir))
      }

      fs::dir_create(destination_dir, recurse = TRUE)
      destination_files <- file.path(destination_dir, basename(files_to_move))

      file.rename(files_to_move, destination_files)

      # # create spatial index for new files (not nessessary for copc)
      # lasR::exec(
      #   lasR::write_lax(embedded = TRUE),
      #   with = list(ncores = lasR::concurrent_files(lasR::half_cores()), progress = TRUE),
      #   on = destination_files
      # )

      # create virtual point cloud for all files in folder
      vpc <- file.path(docufolder, paste0(campaign, "_", year, ".vpc"))
      lasR::exec(
        lasR::write_vpc(ofile = vpc, use_gpstime = TRUE, absolute_path = TRUE),
        with = list(ncores = lasR::concurrent_files(lasR::half_cores()), progress = TRUE),
        on = destination_dir
      )
    }
  }

  unlink(tmpfolder, recursive = TRUE)

  if (verbose) {
    print("Tempfolder deleted")
  }
}
