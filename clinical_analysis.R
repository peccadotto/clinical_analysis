# -----------------------------------------------------------------------------
# SETUP
# -----------------------------------------------------------------------------
  
# 1. Create a vector with the packages to be installed
  packages <- c(
    "bookdown",
    "dplyr",
    "ggplot2",
    "lubridate",
    "rmdformats",
    "tidyverse"
  )
  
# 2. If the package is not installed, then install it
  for (pkg in packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      message("Package '", pkg, "' not found. Installing it...")
      tryCatch(
        install.packages(pkg, dependencies = TRUE),
        error = function(e) {
          message("Error while trying to install the '", pkg, "' package", e$message)
        }
      )
    }
    suppressPackageStartupMessages(library(pkg, character.only = TRUE))
  }
  

# -----------------------------------------------------------------------------
# DATA IMPORT
# -----------------------------------------------------------------------------

# 3. Find unique prefixes in .CSV files' names
  all_files <- list.files(path = 'data', pattern = '\\.csv$')
  prefixes <- unique(str_extract(all_files, "^[A-Z]{3}_"))

# 4. Create a function to import files with a given prefix
  load_by_prefix <- function(prefix) {
    files <- list.files(
      path = 'data',
      pattern = paste0(prefix, '\\d{4}\\.csv'),
      full.names = TRUE
    )
    files |> 
      set_names(basename(files)) |> 
      map_df(~read.csv(
        .x, 
        header = TRUE, 
        sep = ';', 
        na.strings = c('')
      ), .id = "place") |>
      select(!starts_with("X")) |>
      mutate(place = str_sub(place, 1, 3))
  }

# 5. Use the function with all the prefixes and create a final dataframe
  all_data <- prefixes |> 
    set_names(paste0(prefixes, "total")) |>
    map(load_by_prefix)
  clinical_total <- bind_rows(all_data)


# -----------------------------------------------------------------------------    
# DATA CHECK  
# -----------------------------------------------------------------------------
  
# 6. Create a function to search for NA values
  check_missing <- function(df) {
    na_count <- colSums(is.na(df))
    na_pct <- (na_count / nrow(df)) * 100
    results <- data.frame(
      variable = names(na_count),
      missing = na_count,
      pct = round(na_pct, 2),
      row.names = NULL
    )
    results <- results |> arrange(desc(missing))
    return(results)
  }

  
# -----------------------------------------------------------------------------
# DATA TRANSFORMATION
# -----------------------------------------------------------------------------
  
# 7. Set variables classes
  clinical_total <- clinical_total |>
    mutate(
      place = place,
      date = dmy(date),
      time = hms(time),
      service = factor(
        service,
        levels = c("VISORT01", "VISORT02", "ECTBAC", "MISC")
      ),
      type = type,
      type_cat = factor(
        case_when(
          type == "LPN" ~ "Private",
          type == "SSN" ~ "NHS",
          .default = "Insurance"
        ),
        levels = c("Private", "NHS", "Insurance")
      )
    ) |>
    arrange(date, place)
  
# 8. Create new dataframes
  clinical_stats_per_year_wide <- clinical_total |>
    mutate(year = year(date)) |>
    group_by(year) |>
    summarise(
      patients = n(),
      visort01 = sum(service == "VISORT01"),
      visort02 = sum(service == "VISORT02"),
      ectbac = sum(service == "ECTBAC"),
      misc = sum(service == "MISC"),
      insurance  =
        sum(type_cat == "insurance") +
        sum(type_cat == "private")
    )
  
  clinical_stats_per_type_long <- clinical_total |>
    mutate(year = year(date)) |>
    group_by(year, type_cat) |>
    summarise(
      patients = n()
    )
  
  clinical_stats_per_time_wide <- clinical_total |>
    filter(((time >= hms("08:00:00")) & time <= hms("20:00:00"))) |>
    mutate(
      time_cat = case_when(
        time >= hms("08:00:00") & time < hms("10:00:00") ~ "08:00 - 10:00",
        time >= hms("10:00:00") & time < hms("12:00:00") ~ "10:00 - 12:00",
        time >= hms("12:00:00") & time < hms("14:00:00") ~ "12:00 - 14:00",
        time >= hms("14:00:00") & time < hms("16:00:00") ~ "14:00 - 16:00",
        time >= hms("16:00:00") & time < hms("18:00:00") ~ "16:00 - 18:00",
        time >= hms("18:00:00") & time < hms("20:00:00") ~ "18:00 - 20:00"
      )
    ) |>
    mutate(
      time_cat = factor(
        time_cat,
        levels = c(
          "08:00 - 10:00",
          "10:00 - 12:00",
          "12:00 - 14:00",
          "14:00 - 16:00",
          "16:00 - 18:00",
          "18:00 - 20:00")
      )
    ) |>
    group_by(time_cat) |>
    summarise(
      patients = n()
    )
  
  
# -----------------------------------------------------------------------------
# DATA EXPORT
# -----------------------------------------------------------------------------

# 9. Export data for Markdown report
  save(
    check_missing,
    clinical_stats_per_time_wide,
    clinical_stats_per_type_long,
    clinical_stats_per_year_wide,
    clinical_total,
    file = "clinical_analysis.RData"
  )
  
# -----------------------------------------------------------------------------
# ENVIRONMENT CLEANING
# -----------------------------------------------------------------------------

# 10. Delete unnecessary objects from the environment
  obj_to_keep <- c(
    "clinical_stats_per_time_wide",
    "clinical_stats_per_type_long",
    "clinical_stats_per_year_wide",
    "clinical_total"
  )
  rm(list = setdiff(ls(), obj_to_keep))