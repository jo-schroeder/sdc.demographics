# this file estimate demographics to new geographies by directly expand the census geographies (without refining): use the package redistribute
# lets go from block group to zipcode 

# libraries -------------------------------------------------------------
library(dplyr)
library(sf)
library(httr)
library(sp)
library(data.table)
library(stringr)
#library("rgdal", lib.loc="/usr/local/lib/R/site-library")
library(tidyr)
library(readr)
library(tidyverse)
library(tidycensus)
library(tigris)
library(rjson)
library(redistribute)


# load the data -------------------------------------------------------------------
# get the age demographics acs data for virginia
uploadpath = "Veteran/data/distribution/"
files = list.files(uploadpath)
filename = files[str_detect(files,"va_cttrbg_acs")]
acs <- read.csv(paste0(uploadpath,filename))

# prepare the data for modeling -------------------------------------------
# select the census block group for aggregation, select only population count as measure
acs_bg <- acs %>%
  filter(region_type=='block group') %>%
#  filter(!str_detect(measure, "perc")) %>%
  select(geoid,year,measure,value) %>%
  #mutate(measure=str_replace(measure,'veteran_','')) %>%
  pivot_wider(names_from = measure, values_from = value) %>%
  mutate(vetdenom =100*pop_veteran/perc_veteran,
         census_year=if_else(year<2020,2010,2020))

# get census 2010 and 2020
bg_geo_2010 <- sf::read_sf('https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Census%20Geographies/Block%20Group/2010/data/distribution/va_geo_census_cb_2010_census_block_groups.geojson')
bg_geo_2020 <- sf::read_sf('https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Census%20Geographies/Block%20Group/2020/data/distribution/va_geo_census_cb_2020_census_block_groups.geojson')
bg_geo <- rbind(bg_geo_2010,bg_geo_2020) %>%
  select(geoid,year,geometry) %>%
  mutate(census_year=as.numeric(year))

temp_acs <- merge(acs_bg,bg_geo[,c('geoid','census_year','geometry')], by=c('geoid','census_year')) 
temp_acs_sf <- st_as_sf(temp_acs)

# load new geographies geometries
hsr_geo <- sf::st_read("https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Local%20Geographies/Fairfax%20County/Human%20Services%20Regions/2022/data/distribution/va059_geo_ffxct_gis_2022_human_services_regions.geojson")
pd_geo <- sf::st_read("https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Local%20Geographies/Fairfax%20County/Planning%20Districts/2022/data/distribution/va059_geo_ffxct_gis_2022_planning_districts.geojson")
sd_geo <- sf::st_read("https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Local%20Geographies/Fairfax%20County/Supervisor%20Districts/2022/data/distribution/va059_geo_ffxct_gis_2022_supervisor_districts.geojson")
zc_geo <- sf::st_read("https://raw.githubusercontent.com/uva-bi-sdad/sdc.geographies/main/VA/Local%20Geographies/Fairfax%20County/Zip%20Codes/2022/data/distribution/va059_geo_ffxct_gis_2022_zip_codes.geojson")

# get label and geometry separetly
temp_hsr <- hsr_geo %>% select(geoid_hsr=geoid,geometry)
temp_pd <- pd_geo %>% select(geoid_pd=geoid,geometry)
temp_sd <- sd_geo %>% select(geoid_sd=geoid,geometry)
temp_zc <- zc_geo %>% select(geoid_zc=geoid,geometry)


# redistribute the population ---------------------------------------------------
yearlist <- unique(temp_acs_sf$year)
model <- NULL
for (vyear in yearlist){
  subtemp_acs_sf <- temp_acs_sf %>% filter(year==vyear) %>% select(-c('census_year','year'))
  predict_hsr <- redistribute(subtemp_acs_sf, temp_hsr, source_id = "geoid", target_id = 'geoid_hsr')
  #predict_pd <- redistribute(subtemp_acs_sf, temp_pd, source_id = "geoid", target_id = 'geoid_pd')
  predict_sd <- redistribute(subtemp_acs_sf, temp_sd, source_id = "geoid", target_id = 'geoid_sd')
  predict_zc <- redistribute(subtemp_acs_sf, temp_zc, source_id = "geoid", target_id = 'geoid_zc')
  
  # add the year as variable
  predict_hsr <- predict_hsr %>% mutate(year=vyear) %>% st_drop_geometry()
  #predict_pd <- predict_pd %>% mutate(year=vyear) %>% st_drop_geometry()
  predict_sd <- predict_sd %>% mutate(year=vyear) %>% st_drop_geometry()
  predict_zc <- predict_zc %>% mutate(year=vyear) %>% st_drop_geometry()
  
  # combine aggregation over year
  predict <- rbind(predict_hsr,
 #                  predict_pd,
                   predict_sd,
                   predict_zc)
  model <- rbind(model,predict)
}

# estimate the percentage  --------------------------------------------------
model_direct <- model %>%
  mutate(perc_veteran = 100*pop_veteran/vetdenom) %>%
  select(id,year,pop_veteran,perc_veteran) %>%
  pivot_longer(!c('id','year'), names_to = "measure", values_to = "value") %>%
  mutate(
    #measure=paste0('veteran_',measure,'_direct'),
         moe='') %>%
  select(geoid=id,year,measure,value,moe)
  

# combine the data
temp_acs_dmg <- acs %>% 
  select(geoid,year,measure,value,moe) 
temp_direct_dmg <- model_direct 
baseline_data <- rbind(temp_acs_dmg,temp_direct_dmg)

# save the living units distribution ----------------------------------------------------------------------------
savepath = "Veteran/data/distribution/"
readr::write_csv(baseline_data, xzfile(paste0(savepath,"va_hsrsdpdzccttrbg_sdad_",min(yearlist),'_',max(yearlist),"_veteran_demographics1.csv.xz"), compression = 9))





# files = list.files(savepath)
# filename = files[str_detect(files,"va059_hsrsdpdzc_sdad")]
# 
# if (length(filename)==0){
#   # create the file
#   readr::write_csv(model_direct, xzfile(paste0(savepath,"va059_hsrsdpdzc_sdad_",min(yearlist),'_',max(yearlist),"_veteran_demographics.csv.xz"), compression = 9))
#   
# }else{
#   # there is only one file perform check to whether replace the file or update the content
#   file_maxyear = as.numeric(substr(filename,27,30))
#   if(max(yearlist)!=file_maxyear){
#     # update filename
#     file.remove(filename)
#     readr::write_csv(model_direct, xzfile(paste0(savepath,"va059_hsrsdpdzc_sdad_",min(yearlist),'_',max(yearlist),"_veteran_demographics.csv.xz"), compression = 9))
#     
#   }else{
#     #read the file and check if the measure content the model name
#     lastfile <- read.csv(paste0(savepath,filename))
#     lastfile <- rbind(lastfile, model_direct)
#     readr::write_csv(lastfile, xzfile(paste0(savepath,"va059_hsrsdpdzc_sdad_",min(yearlist),'_',max(yearlist),"_veteran_demographics.csv.xz"), compression = 9))
#   }
# }
