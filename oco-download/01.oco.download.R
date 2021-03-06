# Download OCO data for a specific date
# Check functions used to save time and memory by skipping dates, URLs, or files that have already been processed.
#' @param Date POSIXlt date required for downloading
#' @param Write Logical -- if TRUE, write results to fluorescence.csv
#' @param check.dat Logical -- if TRUE, check if current date has already been downloaded
#' @param check.url Logical -- if TRUE, check if URL for file list for a specific date has already been checked for new files
#' @param check.file Logical -- if TRUE, check if specific file has already been downloaded
oco.download.date <- function(Date, Write=TRUE,
                              check.date=TRUE,
                              check.url=TRUE,
                              check.file=TRUE){
    require(rhdf5)
    require(XML)
    require(data.table)

    # Make sure I'm in the project base directory
    if(grepl("-download", getwd())) setwd("..")

    # Create check files
    check.url.file <- "oco-download/checked.urls"
    check.file.file <- "oco-download/checked.files"
    check.date.file <- "oco-download/checked.dates"
    if(!file.exists(check.url.file)) file.create(check.url.file)
    if(!file.exists(check.file.file)) file.create(check.file.file)
    if(!file.exists(check.date.file)) file.create(check.date.file)

    # Set latidue bounding box
    lat.min <- 45
    lat.max <- 47
    lon.min <- -91
    lon.max <- -89

    in.box <- function(lat, lon){
        lat > lat.min & lat < lat.max & lon > lon.min & lon < lon.max
    }

    # Check if date is already in fluorescence. If it is, then skip.
    if(check.date){
        Date.simple <- as.character(as.Date(Date))
        date.exists <- any(grepl(Date.simple, readLines(check.date.file)))
        if(date.exists){
            return("Date exists")
        }
    }
    write(Date.simple, file=check.date.file, append = TRUE)

    # Get all download URLs
    doy <- Date$yday + 1            # Get day of year (need to offset by 1 for some reason)
    year <- Date$year + 1900        # Get current year (years since 1900)
    h5.url.base <- sprintf("http://oco2.gesdisc.eosdis.nasa.gov/opendap/OCO2_L2_IMAPDOAS.7r/%02d/%03d", year, doy)
    h5.url.contents <- paste0(h5.url.base, "/contents.html")

    # Check if URL is already in URL list
    if(check.url){
        url.exists <- any(grepl(h5.url.base, readLines(check.url.file)))
        if(url.exists){
            return("URL exists")
        }
    }

    # Add URL to check file 
    write(h5.url.base, file=check.url.file, append=TRUE)

    # Scrape file list from OCO download page
    h5.raw.table <- try(readHTMLTable(h5.url.contents, stringsAsFactors=FALSE)[[1]])
    if(class(h5.raw.table) == "try-error"){
        warning("Unable to download file list. Check internet connection, or data for today may not be available.")
        return("Unable to download")
    }
    h5.list <- h5.raw.table[grep("oco*", h5.raw.table[,1]),1]

    local.path <- "oco-download/current.h5"

    # Loop over all daily files and save the fluorescence values
    for(h5 in h5.list){
        h5.url <- paste0(h5.url.base, "/", h5)

        # Check for file in check file. Skip if file has already been downloaded
        if(check.file){
            has.file <- any(grepl(h5, readLines(check.file.file)))
            if(has.file){
                message("File already checked. Moving on")
                next
            }
        }
        write(h5, file=check.file.file, append=TRUE)

        # Download file
        download.file(h5.url, local.path, quiet=TRUE)

        # Get latitude and longitude
        lat <- h5read(local.path, "SoundingGeometry/sounding_latitude")
        lon <- h5read(local.path, "SoundingGeometry/sounding_longitude")
        indices <- which(in.box(lat, lon))

        if(length(indices) == 0){
            message("No coordinates in bounding box. Moving to next file")
            next
        } 

        # Get values of fluorescence and time
        measure.list <- data.frame(
            file.name = h5,
            file.url = h5.url,
            measurement.lat = lat[indices],
            measurement.lon = lon[indices],
            measurement.time.raw = h5read(local.path, "SoundingGeometry/sounding_time_string")[indices],
            fluorescence.757 = h5read(local.path, "DOASFluorescence/fluorescence_radiance_757nm_idp")[indices],
            fluorescence.757.unc = h5read(local.path, "DOASFluorescence/fluorescence_radiance_757nm_uncert_idp")[indices],
            fluorescence.771 = h5read(local.path, "DOASFluorescence/fluorescence_radiance_771nm_idp")[indices],
            fluorescence.771.unc = h5read(local.path, "DOASFluorescence/fluorescence_radiance_771nm_uncert_idp")[indices],
            fluorescence.qual.flag = h5read(local.path, "DOASFluorescence/fluorescence_qual_flag_idp")[indices],
            cos.sza = h5read(local.path, "DOASFluorescence/local_daily_avg_cos_sza_idp")[indices]
        )

        measure.list$measurement.time <- strptime(measure.list$measurement.time.raw, "%Y-%m-%dT%H:%M:%S", tz = "GMT")
        measure.list$measurement.date <- strftime(measure.list$measurement.time, "%Y-%m-%d")

        # Append to old fluorescence table
        if(Write){
            csv.path <- "oco-download/fluorescence.csv"
            if(!file.exists(csv.path)){
                write(names(measure.list), file = csv.path, sep=",")
            }
            write.table(measure.list, file = csv.path, sep=",",
                        row.names=FALSE, col.names=FALSE, append=TRUE)
        }
    }
    return(NULL)
}
# Make sure I'm in the project base directory
if(grepl("-download", getwd())) setwd("..")

# Download data up to latest
start.date <- as.POSIXlt("2014-09-07", tz = "GMT")
end.date <- as.POSIXlt(Sys.Date())
Date <- end.date
while(difftime(Date, start.date) > 0){
    message(Date)
    dl <- oco.download.date(Date = Date, Write=TRUE)
    Date <- as.POSIXlt(as.Date(Date) - 1)
}
