library(gridExtra)
library(tidyverse)
library(lubridate)
library(viridis)
library(ggsci)
library(sf)

source("https://raw.githubusercontent.com/matsim-scenarios/matsim-duesseldorf/master/src/main/R/theme.R")

setwd("PLEASE ADJUST TO YOUR LOCAL DIRECTORY FOR matsim-kelheim/src/main/R")

theme_set(theme_Publication(18))

# trip distance groups
levels = c("0 - 1000", "1000 - 2000", "2000 - 5000", "5000 - 10000", "10000 - 20000", "20000+")
breaks = c(0, 1000, 2000, 5000, 10000, 20000, Inf)

shape <- st_read("../../../scenarios/input/shp/dilutionArea.shp", crs=25832)

#########
# Read simulation data
#########

sim_scale <- 4 # set to 4 for 25pct, 10 for 10pct, 100 for 1pct, ...
f <- "../../../output/output-kelheim-25pct/" # set to run output directory

#homes <- read_csv("../../../scenarios/input/kelheim-v2.0-homes.csv", 
#                  col_types = cols(
#                    person = col_character()
#                  ))

persons <- read_delim(list.files(f, pattern = "*.output_persons.csv.gz", full.names = T, include.dirs = F), delim = ";", trim_ws = T, 
                     col_types = cols(
                       person = col_character(),
                       good_type = col_integer()
                     )) %>%
#          right_join(homes) %>%
#          st_as_sf(coords = c("home_x", "home_y"), crs = 25832) %>%
          st_as_sf(coords = c("first_act_x", "first_act_y"), crs = 25832) %>%
          st_filter(shape)

trips <- read_delim(list.files(f, pattern = "*.output_trips.csv.gz", full.names = T, include.dirs = F), delim = ";", trim_ws = T, 
                    col_types = cols(
                      person = col_character()
                    )) %>%
        filter(main_mode!="freight") %>%
        semi_join(persons) %>%
        mutate(dist_group = cut(traveled_distance, breaks=breaks, labels=levels, right = F)) %>%  # traveled_distance == 0 is considered
        filter(!is.na(dist_group))


sim <- trips %>%
  group_by(dist_group, main_mode) %>%
  summarise(trips=n()) %>%
  mutate(mode = fct_relevel(main_mode, "walk", "bike", "pt", "ride", "car")) %>%
  mutate(scaled_trips=sim_scale * trips) %>%
  mutate(source = "sim")

########
# Read survey data
########

srv <- read_csv("mid_adj.csv") %>%
    mutate(main_mode=mode) %>%
    mutate(scaled_trips=122258 * 3.2 * share) %>%
    mutate(source = "mid") %>%
    mutate(dist_group=fct_relevel(dist_group, levels)) %>%
    arrange(dist_group)

######
# Total modal split
#######

srv_aggr <- srv %>%
    group_by(mode) %>%
    summarise(share=sum(share)) %>%  # assume shares sum to 1
    mutate(mode=fct_relevel(mode, "walk", "bike", "pt", "ride", "car"))  
  
aggr <- sim %>%
    group_by(mode) %>%
    summarise(share=sum(trips) / sum(sim$trips)) %>%
    mutate(mode=fct_relevel(mode, "walk", "bike", "pt", "ride", "car"))

p1_aggr <- ggplot(data=srv_aggr, mapping =  aes(x=1, y=share, fill=mode)) +
  labs(subtitle = "Survey data") +
  geom_bar(position="fill", stat="identity") +
  coord_flip() +
  geom_text(aes(label=scales::percent(share, accuracy = 0.1)), size= 3, position=position_fill(vjust=0.5)) +
  scale_fill_locuszoom() +
  theme_void() +
  theme(legend.position="none")

p2_aggr <- ggplot(data=aggr, mapping =  aes(x=1, y=share, fill=mode)) +
  labs(subtitle = "Simulation") +
  geom_bar(position="fill", stat="identity") +
  coord_flip() +
  geom_text(aes(label=scales::percent(share, accuracy = 0.1)), size= 3, position=position_fill(vjust=0.5)) +
  scale_fill_locuszoom() +
  theme_void()

g <- arrangeGrob(p1_aggr, p2_aggr, ncol = 2)
g
out <- file.path(f, "analysis-mode-choice")
if(!file.exists(out)){
  print("creating analysis sub-directory")
  dir.create(out)  
}

ggsave(filename = "modal-split.png", path = out, g,
       width = 12, height = 2, device='png', dpi=300)

#########
# Combined plot by distance
##########

total <- bind_rows(srv, sim) %>%
    mutate(mode=fct_relevel(mode, "walk", "bike", "pt", "ride", "car"))

# Maps left overgroups
dist_order <- factor(total$dist_group, level = levels)
dist_order <- fct_explicit_na(dist_order, "20000+")

g <- ggplot(total, aes(fill=mode, y=scaled_trips, x=source)) +
  labs(subtitle = paste("Kelheim scenario", substring(f, 52)), x="distance [m]", y="trips") +
  geom_bar(position="stack", stat="identity", width = 0.5) +
  facet_wrap(dist_order, nrow = 1) +
  scale_y_continuous(labels = scales::number_format(suffix = " K", scale = 1e-3)) +
  scale_fill_locuszoom() +
  theme_minimal()

g

ggsave(filename = "modal-distance-distribution.png", path = out, g,
       width = 12, height = 10, device='png', dpi=300)


# Needed for adding short distance trips

sim_sum <- sum(sim$trips)
sim_aggr <- sim %>%
  group_by(dist_group) %>%
  summarise(share=sum(trips) / sim_sum)

# Needed share of trips
tripShare <- 0.19
shortDistance <- sum(filter(sim, dist_group=="0 - 1000")$trips)
numTrips = (shortDistance - sim_sum * tripShare) / (tripShare - 1)


##########################
# Distance distributions based on RegioStar data
##########################

levels = c("0 - 500", "500 - 1000", "1000 - 2000", "2000 - 5000", "5000 - 10000", 
           "10000 - 20000", "20000 - 50000", "50000 - 100000", "100000+")

breaks = c(0, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, Inf)

trips2 <- trips %>%
  mutate(dist_group = cut(traveled_distance, breaks=breaks, labels=levels, right = F)) %>%
  mutate(mode = fct_relevel(main_mode, "walk", "bike", "pt", "ride", "car"))

rs <- read_csv("tidied-mode-share-per-distance.csv") %>%
  mutate(source="rs")

sim <- trips2 %>%
  group_by(dist_group) %>%
  summarise(trips=n()) %>%
  mutate(source="sim")

sim <- mutate(sim, share=trips/sum(sim$trips))

total_distance_dist <- bind_rows(filter(rs, mode=="total_distance_distribution"), sim)

dist_order <- factor(total_distance_dist$dist_group, level = levels)
dist_order <- fct_explicit_na(dist_order, "100000+")


g <- ggplot(total_distance_dist, aes(y=share, x=source, fill=source)) +
  labs(subtitle = paste("Kelheim scenario", substring(f, 52)), x="distance [m]", y="share") +
  geom_bar(position="stack", stat="identity", width = 0.5) +
  facet_wrap(dist_order, nrow = 1) +
  scale_fill_viridis_d() +
  theme_minimal()
g

ggsave(filename = "distance-distribution.png", path = out, g,
       width = 12, height = 10, device='png', dpi=300)

##################################

sim <- trips2 %>%
  group_by(dist_group) %>%
  mutate(n=n()) %>%
  group_by(mode, dist_group) %>%
  summarise(share=n()/first(n)) %>%
  mutate(source="sim")

by_distance <- bind_rows(filter(rs, mode!="total_distance_distribution"), sim) %>%
  mutate(mode=fct_relevel(mode, "walk", "bike", "pt", "ride", "car"))

dist_order <- factor(by_distance$dist_group, level = levels)
dist_order <- fct_explicit_na(dist_order, "100000+")

g <- ggplot(by_distance, aes(y=share, x=source, fill=mode)) +
  labs(subtitle = paste("Kelheim scenario", substring(f, 52)), x="distance [m]", y="share") +
  geom_bar(position="stack", stat="identity", width = 0.5) +
  facet_wrap(dist_order, nrow = 1) +
  scale_fill_locuszoom() +
  theme_minimal()
g

ggsave(filename = "modal-distance-distribution-relative.png", path = out, g,
       width = 12, height = 10, device='png', dpi=300)

