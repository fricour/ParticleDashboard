library(data.table)
library(lubridate)
library(tidyverse)

# read index file
index <- fread('/home/fricour/test/argo_bio-profile_index.txt', header = TRUE)

# floats WMO
#WMO <- c(6903093, 3902498, 6904241, 2903783, 1902593, 4903657, 5906970, 4903634, 1902578, 3902471, 4903658, 6990503, 2903787, 4903660, 6990514, 1902601, 4903739, 1902637, 4903740, 2903794, 1902685, 6904240, 7901028)
WMO <- c(3902498, 6904241, 2903783, 1902593, 4903657, 5906970, 4903634, 1902578, 3902471, 4903658, 6990503, 2903787, 4903660, 6990514, 1902601, 4903739, 1902637, 4903740, 2903794, 1902685, 6904240, 7901028)


tmp <- index %>%
  mutate(
    wmo = as.numeric(str_extract(file, "\\d{7}")),
    cycle = as.numeric(str_extract(file, "\\d{3}(?=\\.nc$)")),
    date = ymd(substr(date_update, 1, 8))
  ) %>%
  select(wmo, cycle, latitude, longitude, date) %>%
  filter(wmo %in% WMO) |>
  drop_na()

cat(format_csv(tmp))