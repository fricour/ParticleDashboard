library(tidyverse)
library(purrr)

derive_ost_flux <- function(data, wmo_float){

  # make sure that the cp signal is in chronological order
  tmp <- data %>%
    dplyr::filter(wmo == wmo_float) %>%
    dplyr::arrange(juld)

  # despike cp data with a 7-point moving window
  tmp$cp <- oce::despike(tmp$cp, k = 3)

  # smooth cp data with a 3-point moving median, n time(s)
  tmp$cp <- slide(tmp$cp, fun = median, k = 3, n = 1, na.rm=T)

  # compute slope between two adjacent points (except first point) # we could start after 1h to let the float stabilize
  delta_x <- as.numeric(tmp$juld - dplyr::lag(tmp$juld), units = 'days')
  delta_y <- tmp$cp - dplyr::lag(tmp$cp)
  tmp$slope <- delta_y/delta_x

  # compute a Z score (assuming a normal distribution of the slopes) on the slopes
  tmp <- tmp %>% dplyr::mutate(zscore = (slope - mean(slope, na.rm = T))/sd(slope, na.rm = T))

  # spot outliers on the Z score signal
  # interquartile range between Q25 and Q75 -> had to used that and not the despike function because slopes are often close (or equal) to 0 so it can miss clear jumps. Q25 and Q75 are more trustworthy in this case than the despike function of Jean-Olivier (see package castr on his github: https://github.com/jiho/castr)
  IQR <- quantile(tmp$zscore, probs = 0.75, na.rm=T) - quantile(tmp$zscore, probs = 0.25, na.rm=T)
  # outliers ('spikes' in the Z score signal)
  spikes_down <- tmp$zscore < quantile(tmp$zscore, 0.25, na.rm=T) - 1.5 *IQR
  spikes_up <- tmp$zscore > quantile(tmp$zscore, 0.75, na.rm=T) + 1.5 *IQR
  spikes <- as.logical(spikes_down + spikes_up)

  # assign spikes
  tmp$spikes <- spikes

  # assign colour code to cp signal
  tmp$colour <- 'base signal' # base signal = smoothed despiked cp signal
  tmp[which(tmp$spikes == TRUE),]$colour <- 'jump'

  # add group to compute the slope of each group of points, separated by a jump
  tmp$group <- NA

  # index of jumps in the array
  jump_index <- which(tmp$colour == 'jump')

  # assign group identity to each group of points, separated by a jump (= subgroup)
  for (i in jump_index){
    for (j in 1:nrow(tmp)){
      if ((j < i) & (is.na(tmp$group[j]))){
        tmp$group[j] <- paste0('group_',i)
      }
    }
  }
  tmp$group[which(is.na(tmp$group))] <- 'last_group'

  # compute slope for each subgroup
  slope_df <- tmp %>%
    dplyr::filter(colour == 'base signal', slope != 'NA') %>%
    dplyr::group_by(group) %>%
    dplyr::summarise(min_time = min(juld),
                     max_time = max(juld),
                     nb_points = dplyr::n(),
                     first_cp = cp[1],
                     last_cp = cp[nb_points],
                     delta_x = as.numeric(difftime(max_time, min_time, units = 'days')),
                     delta_y = (last_cp-first_cp)*0.25, slope = delta_y/delta_x) # *0.25 to convert cp to ATN

  # remove negative slope from the mean slope (no physical meaning)
  slope_df <- slope_df %>%
    dplyr::filter(slope > 0)

  # remove if only one point (cannot fit a slope with one point) -> switched to 3 points
  slope_df <- slope_df %>%
    dplyr::filter(nb_points > 3)

  # compute weighted average slope (to take into account the fact that some subgroups might have 2 points and a high slope vs. large group of points with a small slope)
  mean_slope <- sum(slope_df$nb_points * slope_df$slope)/sum(slope_df$nb_points)

  # convert cp to POC using Estapa's relationship
  poc_flux <- 633*(mean_slope**0.77) # /!\ slope computed for ATN on y axis (delta_y *0.25 because ATN = cp*0.25) -> should be OK

  # build dataframe to plot each subgroup
  part1 <- slope_df %>% dplyr::select(group, time = min_time, cp = first_cp)
  part2 <- slope_df %>% dplyr::select(group, time = max_time, cp = last_cp)
  part_slope <- rbind(part1, part2)

  # spot negative jump
  tmp$colour[which((tmp$colour == 'jump') & (tmp$slope < 0))]  <- 'negative jump'

  # add large particles flux to the party
  rows_to_keep <- c(jump_index, jump_index-1)
  tmp2 <- tmp[rows_to_keep,] %>% dplyr::select(juld, cp, slope, colour, group) %>% dplyr::arrange(juld)

  # remove negative jumps, if any
  check_colour <- unique(tmp2$colour)
  if(length(check_colour) >= 2){ # there is a least a jump (positive or negative)
    tmp2 <- tmp2 %>% dplyr::mutate(diff_jump = cp - dplyr::lag(cp))
    even_indexes <- seq(2,nrow(tmp2),2)
    tmp2 <- tmp2[even_indexes,]
  }else{ # No jump
    tmp2 <- NULL
  }

  if(is.null(tmp2)){ # no jump
    large_part_poc_flux <- 0
    tmp3 <- NULL
  }else{
    tmp3 <- tmp2 %>% dplyr::filter(diff_jump > 0)
    if(nrow(tmp3) == 0){ # no positive jumps
      large_part_poc_flux <- 0
    }else{
      delta_y <- sum(tmp3$diff_jump) *0.25 # to get ATN (= cp*0.25)
      max_time <- max(tmp$juld)
      min_time <- min(tmp$juld)
      delta_x <- as.numeric(difftime(max_time, min_time, units = 'days'))
      slope_large_part <- delta_y/delta_x
      large_part_poc_flux <- 633*(slope_large_part**0.77)
    }
  }

  # compute total drifting time
  max_time <- max(tmp$juld)
  min_time <- min(tmp$juld)
  drifting_time <- as.numeric(difftime(max_time, min_time, units = 'days'))

  # to plot subgroups
  part_slope_tmp <- part_slope %>% dplyr::mutate(juld = time, colour = 'slope')

  # plot
  # jump_plot <- plotly::plot_ly(tmp, x = ~juld, y = ~cp, type = 'scatter', mode = 'markers', color = ~colour, colors = c('#003366','#E31B23', '#FFC325')) %>%
  #   plotly::add_lines(data= part_slope_tmp, x = ~juld, y = ~cp, split = ~group, color = I('#DCEEF3'), showlegend = F) %>%
  #   plotly::layout(title= paste0('Drifting time: ', round(drifting_time,3), ' days\n',
  #                        'Mean ATN slope (light blue): ', round(mean_slope,3), ' day-1\n',
  #                        'POC flux (small particles): ', round(poc_flux,1), ' mg C m-2 day-1\n',
  #                        'POC flux (large particles): ', round(large_part_poc_flux,1), ' mg C m-2 day-1'), yaxis = list(title = 'Cp (1/m)'), xaxis = list(title = 'Time'))

  #return(jump_plot)
  #return(list('jump_plot' = jump_plot, 'jump_table' = tmp3))

  # adapt script to return large and small flux
  df <- tibble::tibble('max_time' = max_time, 'min_time' = min_time, 'small_flux' = poc_flux, 'large_flux' = large_part_poc_flux, park_depth = data$park_depth[1], wmo = data$wmo[1],
               cycle = data$cycle[1])

  return(df)
  #return(jump_plot)

}

extract_ost_data <- function(wmo_float, path_to_data){

  # parking depths (so far we only have those 3 but that might change in the future)
  park_depth <- c('200 m', '500 m', '1000 m')

  # extract cp data from the float
  data <- extract_cp_data(wmo_float, path_to_data)

  res <- data.frame()
  max_cycle <- max(data$cycle)
  for (i in park_depth){
    for (j in seq(1:max_cycle)){
      tmp <- data %>% dplyr::filter(park_depth == i, cycle == j)
      if(nrow(tmp) == 0){ # no data for this cycle or at this parking depth
        next
      }else if(nrow(tmp) < 3){ # case where there is not enough data
        next
      }else{
        output <- derive_ost_flux(tmp, wmo_float)
        res <- rbind(res, output)
      }
    }
  }

  return(res)

}