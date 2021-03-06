install.packages("spatstat")
install.packages('GISTools')
install.packages('spdep')
install.packages('fpc')
install.packages('dbscan')
install.packages('ggmap')
library(spatstat)
library(here)
library(sp)
library(rgeos)
library(maptools)
library(GISTools)
library(tmap)
library(sf)
library(geojson)
library(geojsonio)
library(tmaptools)
library(stringr)
library(tidyverse)
library(spdep)
library(raster)
library(fpc)
library(dbscan)
library(OpenStreetMap)
#reading wards
LondonWards <- st_read(here::here("data", "London-wards-2018_ESRI", "London_Ward.shp"))
LondonWardsMerged <- st_read(here::here("data", "London-wards-2018_ESRI",
                                        "London_Ward_CityMerged.shp"))%>%
  st_transform(.,27700)

WardData <- read_csv("https://data.london.gov.uk/download/ward-profiles-and-atlas/772d2d64-e8c6-46cb-86f9-e52b4c7851bc/ward-profiles-excel-version.csv", 
                     na = c("NA", "n/a")) %>% 
  clean_names
spec(WardData)
#LondonWardsMerged <- LondonWardsMerged %>% 
  #left_join(WardData, 
            #by = c("GSS_CODE" = "new_code"))%>%
  #distinct(GSS_CODE, ward_name, average_gcse_capped_point_scores_2014)
st_crs(LondonWardsMerged)

#reading pubs
Pubs <- read_csv("data/Pubs.csv",na = c("NA", "n/a"))
Pubs_spatial <- sf::st_as_sf(Pubs, coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(.,27700)
  
qtm(LondonWardsMerged)
qtm(Pubs_spatial)
#change the ward name to code
#library(plyr) 
#df <- data.frame(foo=norm(1000)) 
#df <- rename(df,c('foo'='samples'))
names(Pubs_spatial)[names(Pubs_spatial) == 'ward_2018_code'] <- 'GSS_CODE'
names(Pubs_spatial)[names(Pubs_spatial) == 'ward_2018_name'] <- 'NAME'
#join data

#LondonWardsMerged_Pub <- LondonWardsMerged
Pubs_spatial <- Pubs_spatial %>%
  add_count(GSS_CODE, name="Pubs_in_ward")
#don't know how to join the don't Let's do spatial autocorrealation
Pubs_sub <- Pubs_spatial[LondonWardsMerged,]
tmap_mode("view")
tm_shape(LondonWardsMerged) +
  tm_polygons(col = NA, alpha = 0.5) +
tm_shape(Pubs_sub) +
  tm_dots(col = "blue")
#mapping the density of points
library(sf)
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  head()
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  st_join(Pubs_spatial) %>%
  head()
Pubs_density <- LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>%
  st_join(Pubs_spatial) %>%
  group_by(GSS_CODE.x) %>% 
  summarize(n_Pubs = n(),
            ward_area = unique(ward_area),
            pubsdensity = n_Pubs/ward_area * 1e6)
plot(Pubs_density["pubsdensity"])
#plot density map
breaks1 <- c(0,0.10,0.65,1.5,3,6.5,15,25,35,50,Inf)
tmap_mode("plot")
tm_shape(Pubs_density) +
  tm_polygons("pubsdensity", 
              style="fixed",
              palette = "OrRd",
              breaks=breaks1,
              title="London \nPubs\nDensity \nper sqKm") +
  tm_scale_bar(position=c("right", "bottom"))

#now for the Moran's I and other statistics
coordsW <- Pubs_density %>%
  st_centroid()%>%
  st_geometry()
plot(coordsW,axes=TRUE)
LWard_nb <- Pubs_density %>%
  poly2nb(., queen=T)
#plot them
plot(LWard_nb, st_geometry(coordsW), col="red")
#add a map underneath, not very clear about the matrix weight part
plot(Pubs_density$geometry, add=T)
Lward.lw <- LWard_nb %>%
  nb2listw(., style="C")

head(Lward.lw$neighbours)
I_LWard_Global_Density <- Pubs_density %>%
  pull(pubsdensity) %>%
  as.vector()%>%
  moran.test(., Lward.lw)

I_LWard_Global_Density
#use the localmoran function to generate I for each ward in the city
I_LWard_Local_count <- Pubs_density %>%
  pull(n_Pubs) %>%
  as.vector()%>%
  localmoran(., Lward.lw)%>%
  as_tibble()

I_LWard_Local_Density <- Pubs_density %>%
  pull(pubsdensity) %>%
  as.vector()%>%
  localmoran(., Lward.lw)%>%
  as_tibble()
#what does the output (the localMoran object) look like?
slice_head(I_LWard_Local_Density, n=5)

#copy some of the columns to the LondonWards spatialPolygonsDataframe
Pubs_density <- Pubs_density %>%
  mutate(pubs_count_I = as.numeric(I_LWard_Local_count$Ii))%>%
  mutate(pubs_count_Iz =as.numeric(I_LWard_Local_count$Z.Ii))%>%
  mutate(density_I =as.numeric(I_LWard_Local_Density$Ii))%>%
  mutate(density_Iz =as.numeric(I_LWard_Local_Density$Z.Ii))

#now plot moran's I
tmap_mode("plot") 
breaks1<-c(-1000,-2.58,-1.96,-1.65,1.65,1.96,2.58,1000)
MoranColours<- rev(brewer.pal(8, "RdGy"))
tm_shape(Pubs_density) +
  tm_polygons("pubs_count_Iz",
              style="fixed",
              breaks=breaks1,
              palette=MoranColours,
              midpoint=NA,
              title="Local Moran's I, Pubs in London")

# now for the Getis Ord G
Gi_LWard_Local_Density <- Pubs_density %>%
  pull(pubsdensity) %>%
  as.vector()%>%
  localG(., Lward.lw)
head(Gi_LWard_Local_Density)
Pubs_density <- Pubs_density %>%
  mutate(density_G = as.numeric(Gi_LWard_Local_Density))
GIColours<- rev(brewer.pal(8, "RdBu"))

#now plot 
tm_shape(Pubs_density) +
  tm_polygons("density_G",
              style="fixed",
              breaks=breaks1,
              palette=GIColours,
              midpoint=NA,
              title="Gi*, Pubs in London")



#now for point analysis, choose borough Westminister and another
LondonBoroughs <- st_read(here::here("data", "statistical-gis-boundaries-london", "ESRI", "London_Borough_Excluding_MHW.shp"))
library(stringr)
BoroughMap <- LondonBoroughs %>%
  dplyr::filter(str_detect(GSS_CODE, "^E09")) %>%
  st_transform(., 27700)
qtm(BoroughMap)
Pubs_spatial_sub <- Pubs_spatial[BoroughMap,]
#check to see that they've been removed
tmap_mode("view")
tm_shape(BoroughMap) +
  tm_polygons(col = NA, alpha = 0.5) +
  tm_shape(Pubs_spatial_sub) +
  tm_dots(col = "blue")
#extract the borough
Westminster <- BoroughMap %>%
  filter(., NAME=="Westminster")
#Check to see that the correct borough has been pulled out
tm_shape(Westminster) +
  tm_polygons(col = NA, alpha = 0.5)
#clip the data to our single borough
Pubs_spatial_sub_W <- Pubs_spatial_sub[Westminster,]
#check that it's worked
tmap_mode("view")
tm_shape(Westminster) +
  tm_polygons(col = NA, alpha = 0.5) +
  tm_shape(Pubs_spatial_sub_W) +
  tm_dots(col = "blue")
#create a ppp object
Pubs_spatial_sub_W <- distinct(Pubs_spatial_sub_W)
window_W <- as.owin(Westminster)
plot(window_W)
Pubs_spatial_sub_W<- Pubs_spatial_sub_W %>%
  as(., 'Spatial')
Pubs_spatial_sub_W.ppp <- ppp(x=Pubs_spatial_sub_W@coords[,1],
                          y=Pubs_spatial_sub_W@coords[,2],
                          window=window_W)
Pubs_spatial_sub_W.ppp %>%
  plot(.,pch=16,cex=0.5, 
       main="Pubs Westminster")
Pubs_spatial_sub_W.ppp %>%
  density(., sigma=500) %>%
  plot()


#let's plot the kenel map of pubs for whole London
Pubs_spatial_sub <- distinct(Pubs_spatial_sub)
window_Brough <- as.owin(BoroughMap)
plot(window_Brough)
Pubs_spatial_sub_All_London<- Pubs_spatial_sub %>%
  as(., 'Spatial')
Pubs_spatial_sub_All_London.ppp <- ppp(x=Pubs_spatial_sub_All_London@coords[,1],
                              y=Pubs_spatial_sub_All_London@coords[,2],
                              window=window_Brough)
Pubs_spatial_sub_All_London.ppp %>%
  plot(.,pch=16,cex=0.5, 
       main="Pubs All London")
Pubs_spatial_sub_All_London.ppp %>%
  density(., sigma=500) %>%
  plot()
#not very good now try the hex
install.packages("fMultivar",depend=TRUE)
library(fMultivar)
hexbin_map <- function(spdf, ...) {
  hbins <- fMultivar::hexBinning(coordinates(spdf),...)
  # Hex binning code block
  # Set up the hexagons to plot,  as polygons
  u <- c(1, 0, -1, -1, 0, 1)
  u <- u * min(diff(unique(sort(hbins$x))))
  v <- c(1,2,1,-1,-2,-1)
  v <- v * min(diff(unique(sort(hbins$y))))/3
  
  # Construct each polygon in the sp model 
  hexes_list <- vector(length(hbins$x),mode='list')
  for (i in 1:length(hbins$x)) {
    pol <- Polygon(cbind(u + hbins$x[i], v + hbins$y[i]),hole=FALSE)
    hexes_list[[i]] <- Polygons(list(pol),i) }
  
  # Build the spatial polygons data frame
  hex_cover_sp <- SpatialPolygons(hexes_list,proj4string=CRS(proj4string(spdf)))
  hex_cover <- SpatialPolygonsDataFrame(hex_cover_sp,
                                        data.frame(z=hbins$z),match.ID=FALSE)
  # Return the result
  return(hex_cover)
}
#now plot, need transforming?
Pubs_spatial_sub_sp <- Pubs_spatial_sub %>%
  as(., 'Spatial')
tmap_mode('view')
pubs_hex <- hexbin_map(Pubs_spatial_sub_sp,bins=200)
tm_shape(pubs_hex) + 
  tm_fill(col='z',title='Pubs Count',alpha=0.7)+
  tm_scale_bar(position=c("right", "bottom"))



#let's mapping the LGBT+nighttime venues and clustering
LGBTnight <- read_csv("data/LGBT_night_time_venues.csv",na = c("NA", "n/a"))
LGBTnight <- sf::st_as_sf(LGBTnight, coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(.,27700)
qtm(LGBTnight)
st_geometry(BoroughMap)
LGBTnight <- distinct(LGBTnight)
window_LGBT <- as.owin(BoroughMap)
plot(window_LGBT)
LGBTnight<- LGBTnight %>%
  as(., 'Spatial')
LGBTnight.ppp <- ppp(x=LGBTnight@coords[,1],
                              y=LGBTnight@coords[,2],
                              window=window_LGBT)
K <- LGBTnight.ppp %>%
  Kest(., correction="border") %>%
  plot()
#first extract the points from the spatial points data frame
LGBTnightPoints <- LGBTnight %>%
  coordinates(.)%>%
  as.data.frame()

#now run the dbscan analysis
db <- LGBTnightPoints %>%
  fpc::dbscan(.,eps = 1000, MinPts = 4)

#now plot the results
plot(db, LGBTnightPoints, main = "DBSCAN Output", frame = F)
plot(BoroughMap$geometry, add=T)

#imorove the map
LGBTnightPoints%>%
  dbscan::kNNdistplot(.,k=4)
library(ggplot2)
LGBTnightPoints<- LGBTnightPoints %>%
  mutate(dbcluster=db$cluster)
chulls <- LGBTnightPoints %>%
  group_by(dbcluster) %>%
  dplyr::mutate(hull = 1:n(),
                hull = factor(hull, chull(coords.x1, coords.x2)))%>%
  arrange(hull)
chulls <- chulls %>%
  filter(dbcluster >=1)
dbplot <- ggplot(data=LGBTnightPoints, 
                 aes(coords.x1,coords.x2, colour=dbcluster, fill=dbcluster)) 
#add the points in
dbplot <- dbplot + geom_point()
#now the convex hulls
dbplot <- dbplot + geom_polygon(data = chulls, 
                                aes(coords.x1,coords.x2, group=dbcluster), 
                                alpha = 0.5) 
#now plot, setting the coordinates to scale correctly and as a black and white plot 
#(just for the hell of it)...
dbplot + theme_bw() + coord_equal()

#now let's add base map
library(OpenStreetMap)
BoroughMapGSbb <- BoroughMap %>%
  st_transform(., 4326)%>%
  st_bbox()
basemap <- OpenStreetMap::openmap(c(51.60494,-0.30000),c(51.40401,0.06042),
                                  zoom=NULL,
                                  "stamen-toner")
# convert the basemap to British National Grid
basemap_bng <- openproj(basemap, projection="+init=epsg:27700")
# now plot the results
OpenStreetMap::autoplot.OpenStreetMap(basemap_bng) + 
  geom_point(data=LGBTnightPoints, 
             aes(coords.x1,coords.x2, 
                 colour=dbcluster, 
                 fill=dbcluster)) + 
  geom_polygon(data = chulls, 
               aes(coords.x1,coords.x2, 
                   group=dbcluster,
                   fill=dbcluster), 
               alpha = 0.5)  



#let's mapping the other venues at night. Theater Cinema Music
#reading 
Theatres <- read_csv("data/Theatres.csv",na = c("NA", "n/a"))
Theatres <- sf::st_as_sf(Theatres, coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(.,27700)

qtm(LondonWardsMerged)
qtm(Theatres)
#change the ward name to code
#library(plyr) 
#df <- data.frame(foo=norm(1000)) 
#df <- rename(df,c('foo'='samples'))
names(Theatres)[names(Theatres) == 'ward_2018_code'] <- 'GSS_CODE'
names(Theatres)[names(Theatres) == 'ward_2018_name'] <- 'NAME'
#join data
#LondonWardsMerged_Pub <- LondonWardsMerged
Theatres <- Theatres %>%
  add_count(GSS_CODE, name="Pubs_in_ward")
#don't know how to join the don't Let's do spatial autocorrealation
Theatres <- Theatres[LondonWardsMerged,]
tmap_mode("view")
tm_shape(LondonWardsMerged) +
  tm_polygons(col = NA, alpha = 0.5) +
  tm_shape(Theatres) +
  tm_dots(col = "blue")
#mapping the density of points
library(sf)
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  head()
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  st_join(Theatres) %>%
  head()
Theatres_density <- LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>%
  st_join(Theatres) %>%
  group_by(GSS_CODE.x) %>% 
  summarize(n_Theatres = n(),
            ward_area = unique(ward_area),
            theatredensity = n_Theatres/ward_area * 1e6)
plot(Theatres_density["theatredensity"])
#plot density map
library(tmap)
breaks1 <- c(0,0.10,0.65,1.5,3,6.5,15,25,35,50,Inf)
tmap_mode("plot")
tm_shape(Theatres_density) +
  tm_polygons("theatredensity", 
              style="fixed",
              palette = "OrRd",
              breaks=breaks1,
              title="London \nTheatres\nDensity \nper sqKm") +
  tm_scale_bar(position=c("right", "bottom"))



#reading next
Cinemas <- read_csv("data/Cinemas.csv",na = c("NA", "n/a"))
Cinemas <- sf::st_as_sf(Cinemas, coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(.,27700)

qtm(LondonWardsMerged)
qtm(Cinemas)
#change the ward name to code
#library(plyr) 
#df <- data.frame(foo=norm(1000)) 
#df <- rename(df,c('foo'='samples'))
names(Cinemas)[names(Cinemas) == 'ward_2018_code'] <- 'GSS_CODE'
names(Cinemas)[names(Cinemas) == 'ward_2018_name'] <- 'NAME'
#join data
#LondonWardsMerged_Pub <- LondonWardsMerged
Cinemas <- Cinemas %>%
  add_count(GSS_CODE, name="Cinemas_in_ward")
#don't know how to join the don't Let's do spatial autocorrealation
Cinemas <- Cinemas[LondonWardsMerged,]
tmap_mode("view")
tm_shape(LondonWardsMerged) +
  tm_polygons(col = NA, alpha = 0.5) +
  tm_shape(Cinemas) +
  tm_dots(col = "blue")
#mapping the density of points
library(sf)
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  head()
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  st_join(Cinemas) %>%
  head()
Cinemas_density <- LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>%
  st_join(Cinemas) %>%
  group_by(GSS_CODE.x) %>% 
  summarize(n_Cinemas = n(),
            ward_area = unique(ward_area),
            cinemasdensity = n_Cinemas/ward_area * 1e6)
plot(Cinemas_density["cinemasdensity"])
#plot density map
library(tmap)
breaks1 <- c(0,0.10,0.65,1.5,3,6.5,15,25,35,50,Inf)
tmap_mode("plot")
tm_shape(Cinemas_density) +
  tm_polygons("cinemasdensity", 
              style="fixed",
              palette = "OrRd",
              breaks=breaks1,
              title="London \nCinemas\nDensity \nper sqKm") +
  tm_scale_bar(position=c("right", "bottom"))



#reading the last one lets finish this!!
Music <- read_csv("data/Music_venues_all.csv",na = c("NA", "n/a"))
Music <- sf::st_as_sf(Music, coords = c("longitude", "latitude"), crs = 4326) %>%
  st_transform(.,27700)

qtm(LondonWardsMerged)
qtm(Music)
#change the ward name to code
#library(plyr) 
#df <- data.frame(foo=norm(1000)) 
#df <- rename(df,c('foo'='samples'))
names(Music)[names(Music) == 'ward_2018_code'] <- 'GSS_CODE'
names(Music)[names(Music) == 'ward_2018_name'] <- 'NAME'
#join data
#LondonWardsMerged_Pub <- LondonWardsMerged
Music <- Music %>%
  add_count(GSS_CODE, name="Music_in_ward")
#don't know how to join the don't Let's do spatial autocorrealation
Music <- Music[LondonWardsMerged,]
tmap_mode("view")
tm_shape(LondonWardsMerged) +
  tm_polygons(col = NA, alpha = 0.5) +
  tm_shape(Music) +
  tm_dots(col = "blue")
#mapping the density of points
library(sf)
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  head()
LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>% 
  st_join(Music) %>%
  head()
Music_density <- LondonWardsMerged %>% 
  mutate(ward_area = st_area(geometry)) %>%
  st_join(Music) %>%
  group_by(GSS_CODE.x) %>% 
  summarize(n_Music = n(),
            ward_area = unique(ward_area),
            musicdensity = n_Music/ward_area * 1e6)
plot(Music_density["musicdensity"])
#plot density map
library(tmap)
breaks1 <- c(0,0.10,0.65,1.5,3,6.5,15,25,35,50,Inf)
tmap_mode("plot")
tm_shape(Music_density) +
  tm_polygons("musicdensity", 
              style="fixed",
              palette = "OrRd",
              breaks=breaks1,
              title="London \nMusic venues\nDensity \nper sqKm") +
  tm_scale_bar(position=c("right", "bottom"))

