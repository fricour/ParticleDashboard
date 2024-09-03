extract_LPM <- function(ncfile){

  # open NetCDF
  nc_data <- try(ncdf4::nc_open(ncfile))
  if(class(nc_data) == 'try-error'){
    return(0)
  }else{
    # extract pressure field
    pres <- ncdf4::ncvar_get(nc_data, 'PRES')
    # extract measurement code
    mc <- ncdf4::ncvar_get(nc_data, 'MEASUREMENT_CODE')
    # extract time
    juld <- ncdf4::ncvar_get(nc_data, 'JULD')
    # extract cycle number
    cycle <- ncdf4::ncvar_get(nc_data, 'CYCLE_NUMBER')
    # extract wmo (and remove leading and trailing whitespaces)
    wmo <- stringr::str_trim(ncdf4::ncvar_get(nc_data, 'PLATFORM_NUMBER'))

    # extract particle size spectra
    part_spectra <- try(ncdf4::ncvar_get(nc_data, 'NB_SIZE_SPECTRA_PARTICLES'))

    if(class(part_spectra)[1] != 'try-error'){

      # transpose part spectra matrix
      part_spectra <- tibble::as_tibble(t(part_spectra))
      # lpm classes
      lpm_classes <- c('NP_Size_50.8','NP_Size_64','NP_Size_80.6', 'NP_Size_102','NP_Size_128','NP_Size_161','NP_Size_203',
                       'NP_Size_256','NP_Size_323','NP_Size_406','NP_Size_512','NP_Size_645','NP_Size_813','NP_Size_1020','NP_Size_1290',
                       'NP_Size_1630','NP_Size_2050','NP_Size_2580')
      # rename columns
      colnames(part_spectra) <- lpm_classes

      # extract number of images
      image_number <- ncdf4::ncvar_get(nc_data, 'NB_IMAGE_PARTICLES')

      # divide particle concentrations by number of images
      part_spectra <- part_spectra |>
       dplyr::mutate(dplyr::across(NP_Size_50.8:NP_Size_2580, ~.x/(0.7*image_number))) # 0.7 = UVP6 image volume

      # add depth/juld/cycle to part_spectra
      part_spectra$depth <- pres
      part_spectra$mc <- mc
      part_spectra$cycle <- cycle
      part_spectra$juld <- juld
      part_spectra$wmo <- as.character(wmo)

      # convert julian day to human time
      part_spectra <- part_spectra |>
       dplyr::mutate(juld = oce::argoJuldToTime(juld))

      # drop NA in particle size spectra
      part_spectra <- part_spectra |>
       tidyr::drop_na(NP_Size_50.8)

      # keep data when the float is parked
      part_spectra <- part_spectra |>
        dplyr::filter(mc == 290) |>
        dplyr::select(-mc)

      # define "standard" parking depths (200 m, 500 m and 1000 m)
      part_spectra <- part_spectra |>
       dplyr::mutate(park_depth = dplyr::if_else(depth < 350, 200, dplyr::if_else(depth > 750, 1000, 500)))

      # reorder tibble
      part_spectra <- part_spectra |>
       dplyr::select(depth, park_depth, cycle, juld, dplyr::everything())

      # remove some weird numbers associated to BAD QCs (but all QCs are at 0 so not JULD_QC is not useful here)
      part_spectra <- part_spectra |>
       dplyr::filter(juld > '2021-01-01', juld < '2025-01-01')

      # format data
      part_spectra$juld <- format(part_spectra$juld, "%Y-%m-%d")

      # close NetCDF
      ncdf4::nc_close(nc_data)

      return(part_spectra)
    }else{ # no particle data in the NetCDF
      return(0)
    }
  }
}

compute_spectral_slope <- function(wmo_float, path_to_data){

  # extract UVP data at parking
  ncfile <- paste0(path_to_data,wmo_float,'/',wmo_float,'_Rtraj_aux.nc')
  data <- extract_LPM(ncfile)

  # particle size classes
  #print(wmo_float)
  lpm_classes <- c('NP_Size_102','NP_Size_128','NP_Size_161','NP_Size_203',
                   'NP_Size_256','NP_Size_323','NP_Size_406','NP_Size_512','NP_Size_645','NP_Size_813','NP_Size_1020','NP_Size_1290',
                   'NP_Size_1630','NP_Size_2050')

  # "center" of the size bin (pseudo center with a geometric progression of 2/3) of each size bin
  mid_DSE <- c(0.1147968,0.1446349,0.1822286,0.2295937,0.2892699,0.3644572,0.4591873,0.5785398,0.7289145,0.9183747,1.1570796,1.4578289,1.83674934,2.31415916)

  # length of the size bin
  size_bin <- c(0.02640633,0.03326989,0.04191744,0.05281267,0.06653979,0.08383488,0.10562533,0.13307958,0.16766976,0.21125066,0.26615915,0.33533952,0.422501323,0.532318310)

  # keep useful columns
  data <- data |>
    dplyr::mutate(wmo = wmo_float) |>
    dplyr::select(wmo, juld, cycle, depth, dplyr::all_of(lpm_classes)) |>
    tidyr::drop_na() |>
    dplyr::filter((NP_Size_102 > 0) & (is.finite(NP_Size_102))) # remove data when the smallest size class is 0 or non finite -> could indicate an instrument failure

  # compute slope
  particle_spectra <- as.matrix(data |> dplyr::select(dplyr::all_of(lpm_classes)))
  index <- seq(from = 1, to = nrow(particle_spectra), by = 1)
  slopes <- purrr::map_dbl(index, compute_slope, data_spectra = particle_spectra, mid_DSE = mid_DSE, size_bin = size_bin)
  data$spectral_slope <- slopes

  # clean data and compute daily mean slope
  data <- data |>
    dplyr::select(-dplyr::all_of(lpm_classes)) |>
    dplyr::mutate(park_depth = dplyr::if_else(depth < 350, 200, dplyr::if_else(depth > 750, 1000, 500))) |>
    dplyr::mutate(date = lubridate::as_datetime(juld)) |>
    dplyr::group_by(wmo, cycle, park_depth, date) |>
    dplyr::summarize(mean_slope = mean(spectral_slope, na.rm=T))

  return(data)

}

compute_slope <- function(i, data_spectra, mid_DSE, size_bin){

  spectrum <- data_spectra[i,]

  spectrum_norm <- spectrum/size_bin

  # prepare data for linear regression
  Y <- log(spectrum_norm)
  X <- log(mid_DSE)

  # check for finite value
  h <- is.finite(Y)
  Y <- Y[h]
  X <- X[h]

  data_slope <- tibble::tibble(X=X, Y=Y)

  model <- stats::lm(formula = Y ~ X, data = data_slope)
  slope <- model$coefficients[2]

  return(slope)
}

WMO <- c(1902578, 1902593, 1902601, 1902637, 1902685, 2903783, 2903787, 2903794, 3902471, 3902498, 4903634, 4903657, 4903658, 4903660, 4903739, 4903740, 5906970, 6904240, 6904241, 6990503, 6990514, 7901028)

tmp <- purrr::map_dfr(WMO, compute_spectral_slope, path_to_data = '/home/fricour/test/argo_trajectory_files/')

# clean for format_csv
tmp <- tmp |>
    dplyr::mutate(cycle = as.numeric(cycle)) |>
    dplyr::mutate(wmo = as.character(wmo)) |>
    dplyr::mutate(zone = dplyr::case_when(
     wmo %in% c(6904240, 6904241, 1902578, 4903634) ~ 'Labrador Sea',
     wmo %in% c(4903660, 6990514) ~ 'Arabian Sea',
     wmo %in% c(3902498, 1902601) ~ 'Guinea Dome',
     wmo %in% c(1902637, 4903740, 4903739) ~ 'Apero mission',
     wmo %in% c(2903787, 4903657) ~ 'West Kerguelen',
     wmo %in% c(1902593, 4903658) ~ 'East Kerguelen',
     wmo %in% c(5906970, 3902473, 6990503, 3902471) ~ 'Tropical Indian Ocean',
     wmo %in% c(2903783) ~ 'South Pacific Gyre',
     wmo %in% c(6903093, 6903094) ~'California Current',
     wmo %in% c(7901028, 2903794) ~ 'Nordic Seas',
     wmo %in% c(1902685) ~ 'North Pacific Gyre',
     .default = NA
    )) 


#compute_spectral_slope(WMO[1], '/home/fricour/test/argo_trajectory_files/')
#cat(readr::format_csv(tmp))

temp_file <- tempfile(fileext = ".parquet")
arrow::write_parquet(tmp, sink = temp_file)

system2('/bin/cat', args = temp_file)
