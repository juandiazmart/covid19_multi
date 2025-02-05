library(cmdstanr)
library(posterior)
library(bayesplot)
library(dplyr)
library(tidybayes)
library(readr)
library(rjson)
library(loo)
library(ggplot2)
library(tidyverse)

#set working directory to covid19_multi


color_scheme_set("red")
datos=readRDS("Data/datos.rds")
mdat=datos$muerte
hdat=datos$hosp

#options(mc.cores = parallel::detectCores())

################
### jer2modi ###
################

mod_jer2modi <- cmdstan_model("./CC2/jer2modi/ModeloJer2QRhosp_quant.stan")

json_data_jer2modi <- fromJSON(file="./Cmdstan/jer_2modi.json")

fit_jer2modi <- mod_jer2modi$generate_quantities(c("./CC2/jer2modi/jer2modi_1.csv",
                                                   "./CC2/jer2modi/jer2modi_2.csv",
                                                   "./CC2/jer2modi/jer2modi_3.csv"), data = "./Cmdstan/jer_2modi.json",
                                                 parallel_chains = 3)
  

#############################
### LongFormat_y_re_mort  ###
### LongFormat_y_re_hostp ###
#############################

#Ultima actualizacion: se utilizo solo una cadena para generar los long format, no tres

generateLong_hosp = F
generateLong_mort = F

if(generateLong_hosp) {
  
  df_hosp =as_draws_df(fit_jer2modi$draws("y_hosp_tilde")) %>% group_by(.chain) %>%
    filter(.draw %in% 1:10) %>% ungroup()
  
  longFormat_y_rep_hosp = gather_draws(df_hosp,y_hosp_tilde[id])
  
  Estados_h = hdat %>% mutate(id=row_number()) %>% select(ENTIDAD_UM,id)
  
  longFormat_y_rep_hosp <- left_join(Estados_h,longFormat_y_rep_hosp,by=c("id"="id")) %>%
    #write_csv("~/Documents/Github/covid19_epi/data/longFormat_y_rep_hosp.csv")
    write_csv("~/covid19_epi/data/longFormat_y_rep_hosp.csv")
  
}

if(generateLong_mort) {
  
  df_mort = as_draws_df(fit_jer2modi$draws("y_mort_tilde")) %>% group_by(.chain) %>%
    filter(.draw %in% 1:10) %>% ungroup()
  
  longFormat_y_rep_mort = gather_draws(df_mort,y_mort_tilde[id])
  
  Estados_m = mdat %>% mutate(id=row_number()) %>% select(ENTIDAD_UM,id)
  
  longFormat_y_rep_mort <- left_join(Estados_m,longFormat_y_rep_mort,by=c("id"="id")) %>%
    #write_csv("~/Documents/Github/covid19_epi/data/longFormat_y_rep_mort.csv")
    write_csv("~/covid19_epi/data/longFormat_y_rep_mort.csv")
}


##########################
### plots ppc jer2modi ###
##########################

y_rep_hosp=fit_jer2modi$draws("y_hosp_tilde")
y_rep_hosp=as_draws_matrix(y_rep_hosp)

ppc_plot_modi_hosp <- ppc_dens_overlay(json_data_jer2modi$y_hosp,y_rep_hosp[1:200,])

ggsave("./CC2/jer2modi/ppc_plot_modi_hosp.png",ppc_plot_modi_hosp,width = 23.05,height = 17.57,units="cm",bg="white")


y_rep_mort=fit_jer2modi$draws("y_mort_tilde")
y_rep_mort=as_draws_matrix(y_rep_mort)

ppc_plot_modi_mort <- ppc_dens_overlay(json_data_jer2modi$y_mort,y_rep_mort[1:200,]) + 
  labs(x="Days from hospitalization to death")

ggsave("./CC2/jer2modi/ppc_plot_modi_mort.png",ppc_plot_modi_mort,width = 23.05,height = 17.57,units="cm", bg="white")


###############################
### mcmc intervals jer2modi ###
###############################

intervals_jer2modi=read_cmdstan_csv(files = 
                                      c("./CC2/jer2modi/jer2modi_1.csv","./CC2/jer2modi/jer2modi_2.csv",
                                        "./CC2/jer2modi/jer2modi_3.csv"))

ylabs_mu_l2_intervals_jer2modi = str_replace_all(levels(mdat$SECENT),c("ESTATAL" = "State managed",
                                      "SE_MAR_PE" = "SEDENA/SEMAR/PEMEX", 
                                      "SSA_OTROS" = "SSA",
                                      "PRIVADA"= "Private healthcare provider"))

mu_l2_intervals_jer2modi <- mcmc_intervals(intervals_jer2modi$post_warmup_draws,regex_pars = c("mu_l2\\W"),prob_outer = .95) +
  ggplot2::labs( x="Log Hazard Ratio"
                 #,title = "Mu_l2 Jer2"
                 ) +
  scale_y_discrete(labels=rev(ylabs_mu_l2_intervals_jer2modi),limits=rev)

ggsave("./CC2/jer2modi/mu_12_intervalsjer2modi.png",mu_l2_intervals_jer2modi,width = 23.05,height = 52.71,units="cm",bg="white")


mu_l_intervals_jer2modi <- mcmc_intervals(intervals_jer2modi$post_warmup_draws,regex_pars = c("mu_l\\W"),prob_outer = .95) +
  ggplot2::labs( x="Log Hazard Ratio"
                 #,title = "Mu_l2 Jer2"
  ) +
  scale_y_discrete(labels=rev(levels(mdat$ENTIDAD_UM)),limits=rev)

ggsave("./CC2/jer2modi/mu_l_intervalsjer2modi.png",mu_l_intervals_jer2modi,width = 23.05,height = 17.57,units="cm",bg="white")

#x=model.matrix(~DIABETES+EPOC+OBESIDAD+HIPERTENSION+DIABETES*OBESIDAD*HIPERTENSION+
#                 SEXO+RENAL_CRONICA+EDAD,data=mdat)

###############################
### Beta intervals jer2modi ###
###############################

beta_m_jer2modi=as_draws_df(fit_jer2modi$draws("beta"))

out_all_beta_m_jer2modi = beta_m_jer2modi %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_intervals_jer2modi = mcmc_intervals(exp(-beta_m_jer2modi),regex_pars = "beta",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta[1]"="Diabetes",
             "beta[2]"="COPD",
             "beta[3]"="Obesity",
             "beta[4]"="Hypertension",
             "beta[5]"="Female",
             "beta[6]"="Chronic Kidney",
             "beta[7]"="Age",
             "beta[8]"="Semaforo",
             "beta[9]"="Diabetes : obesity",
             "beta[10]"="Diabetes : Hypertension",
             "beta[11]"="Obesity : Hypertension",
             "beta[12]"="Diabetes : Obesity : Hypertension"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.74,1.45)) +
  geom_text(
    data = out_all_beta_m_jer2modi,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.45),
    hjust = "inward"
  )

ggsave("./CC2/jer2modi/beta_intervalsjer2modi.png",beta_intervals_jer2modi,width = 23.05,height = 17.57,units="cm",bg="white")


#x_hosp=model.matrix(~EPOC+OBESIDAD+RENAL_CRONICA+ASMA+INMUSUPR+SEXO+EDAD,data=hdat)

beta_h_m_jer2modi=as_draws_df(fit_jer2modi$draws("beta_h"))

out_all_beta_h_m_jer2modi = beta_h_m_jer2modi %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_h_intervals_jer2modi = mcmc_intervals(exp(-beta_h_m_jer2modi),regex_pars = "beta_h",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta_h[1]"="COPD",
             "beta_h[2]"="Obesity",
             "beta_h[3]"="Chronic Kidney",
             "beta_h[4]"="Asthma",
             "beta_h[5]"="Immunosuppression",
             "beta_h[6]"="Female",
             "beta_h[7]"="Age",
             "beta_h[8]"="Semaforo"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.9,1.3)) +
  geom_text(
    data = out_all_beta_h_m_jer2modi,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.3),
    hjust = "inward"
  )

ggsave("./CC2/jer2modi/beta_h_intervalsjer2modi.png",beta_h_intervals_jer2modi,width = 23.05,height = 17.57,units="cm",bg = "white")

####################
### loo jer2modi ###
####################

#loo_hosp_jer2modi=loo(fit_jer2modi$draws("log_lik_hosp"), r_eff = NA)

loo_mort_jer2modi=loo(fit_jer2modi$draws("log_lik_mort"), r_eff = NA)
#saveRDS(loo_mort_jer2modi,"./CC2/jer2modi/loo_mort_jer2modi.rds")

#loo_compare(loo1, loo2)



############
### jer2 ###
############

mod_jer2 <- cmdstan_model("./CC2/jer2/ModeloJer2QR_quant.stan")

json_data_jer2 <- fromJSON(file="./Cmdstan/jer_2.json")

fit_jer2 <- mod_jer2$generate_quantities(c("./CC2/jer2/jer2_1.csv","./CC2/jer2/jer2_2.csv",
                                           "./CC2/jer2/jer2_3.csv"), data = "./Cmdstan/jer_2.json",  
                                         parallel_chains = 3)


######################
### plots ppc jer2 ###
######################

y_rep_hosp=fit_jer2$draws("y_hosp_tilde")
y_rep_hosp=as_draws_matrix(y_rep_hosp)
y_rep_mort=fit_jer2$draws("y_mort_tilde")
y_rep_mort=as_draws_matrix(y_rep_mort)

ppc_plot_jer2_mort <- ppc_dens_overlay(json_data_jer2$y_mort,y_rep_mort[1:200,]) + 
  labs(x="Days from hospitalization to death")

ggsave("./CC2/jer2/ppc_plot_jer2_mort.png",ppc_plot_jer2_mort,width = 23.05,height = 17.57,units="cm",bg = "white")



ppc_plot_jer2_hosp <- ppc_dens_overlay(json_data_jer2$y_hosp,y_rep_hosp[1:200,])

ggsave("./CC2/jer2/ppc_plot_jer2_hosp.png",ppc_plot_jer2_hosp,width = 23.05,height = 17.57,units="cm",bg="white")

###########################
### mcmc intervals jer2 ###
###########################

intervals_jer2=read_cmdstan_csv(files = c("./CC2/jer2/jer2_1.csv","./CC2/jer2/jer2_2.csv","./CC2/jer2/jer2_3.csv"))
int_jer2_post=as_draws_matrix(intervals_jer2$post_warmup_draws)

ylabs_mu_l2_intervals_jer2 = str_replace_all(levels(mdat$SECTOR),c("ESTATAL" = "State managed",
                                                                   "SE_MAR_PE" = "SEDENA/SEMAR/PEMEX", 
                                                                   "SSA_OTROS" = "SSA",
                                                                   "PRIVADA"= "Private healthcare provider"))

mu_l2_intervals_jer2 = mcmc_intervals(int_jer2_post,regex_pars = "mu_l2\\W",prob_outer = .95) + 
  labs(x="Log Hazard Ratio") + 
  scale_y_discrete(labels=rev(ylabs_mu_l2_intervals_jer2),limits=rev)

ggsave("./CC2/jer2/mu_12_intervalsjer2.png",mu_l2_intervals_jer2,width = 23.05,height = 17.57,units="cm")



mu_l_intervals_jer2 = mcmc_intervals(int_jer2_post,regex_pars = "mu_l\\W",prob_outer = .95) + 
  labs(x="Log Hazard Ratio") + 
  scale_y_discrete(labels=rev(c(levels(mdat$ENTIDAD_UM))),limits=rev)

ggsave("./CC2/jer2/mu_1_intervalsjer2.png",mu_l_intervals_jer2,width = 23.05,height = 17.57,units="cm")


#x=model.matrix(~DIABETES+EPOC+OBESIDAD+HIPERTENSION+DIABETES*OBESIDAD*HIPERTENSION+
#                 SEXO+RENAL_CRONICA+EDAD,data=mdat)

beta_m_jer2=as_draws_df(fit_jer2$draws("beta"))

out_all_beta_m_jer2 = beta_m_jer2 %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_intervals_jer2 = mcmc_intervals(exp(-beta_m_jer2),regex_pars = "beta",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta[1]"="Diabetes",
             "beta[2]"="COPD",
             "beta[3]"="Obesity",
             "beta[4]"="Hypertension",
             "beta[5]"="Female",
             "beta[6]"="Chronic Kidney",
             "beta[7]"="Age",
             "beta[8]"="Semaforo",
             "beta[9]"="Diabetes : obesity",
             "beta[10]"="Diabetes : Hypertension",
             "beta[11]"="Obesity : Hypertension",
             "beta[12]"="Diabetes : Obesity : Hypertension"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.74,1.45)) +
  geom_text(
    data = out_all_beta_m_jer2,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.45),
    hjust = "inward"
  )

ggsave("./CC2/jer2/beta_intervalsjer2.png",beta_intervals_jer2,width = 23.05,height = 17.57,units="cm",bg="white")


#x_hosp=model.matrix(~EPOC+OBESIDAD+RENAL_CRONICA+ASMA+INMUSUPR+SEXO+EDAD,data=hdat)

beta_h_m_jer2=as_draws_df(fit_jer2$draws("beta_h"))

out_all_beta_h_m_jer2 = beta_h_m_jer2 %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_h_intervals_jer2 = mcmc_intervals(exp(-beta_h_m_jer2),regex_pars = "beta_h",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta_h[1]"="COPD",
             "beta_h[2]"="Obesity",
             "beta_h[3]"="Chronic Kidney",
             "beta_h[4]"="Asthma",
             "beta_h[5]"="Immunosuppression",
             "beta_h[6]"="Female",
             "beta_h[7]"="Age",
             "beta_h[8]"="Semaforo"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.9,1.3)) +
  geom_text(
    data = out_all_beta_h_m_jer2,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.3),
    hjust = "inward"
  )

ggsave("./CC2/jer2/beta_h_intervalsjer2.png",beta_h_intervals_jer2,width = 23.05,height = 17.57,units="cm",bg = "white")

################
### loo jer2 ###
################

#loo_hosp_jer2=loo(fit_jer2$draws("log_lik_hosp"), r_eff = NA)

loo_mort_jer2=loo(fit_jer2$draws("log_lik_mort"), r_eff = NA)
#saveRDS(loo_mort_jer2,"./CC2/jer2/loo_mort_jer2.rds")


############
### jer1 ###
############

mod_jer1 <- cmdstan_model("./CC2/jer1/ModeloJerQR_quant.stan")

json_data_jer1 <- fromJSON(file="./Cmdstan/jer_1.json")

fit_jer1<- mod_jer1$generate_quantities(c("./CC2/jer1/jer1_1.csv","./CC2/jer1/jer1_2.csv",
                                          "./CC2/jer1/jer1_3.csv"), data = "./Cmdstan/jer_1.json",  
                                        parallel_chains = 3)


######################
### plots ppc jer1 ###
######################

y_rep_hosp=fit_jer1$draws("y_hosp_tilde")
y_rep_hosp=as_draws_matrix(y_rep_hosp)

ppc_plot_jer1_hosp <- ppc_dens_overlay(json_data_jer1$y_hosp,y_rep_hosp[1:200,])

ggsave("./CC2/jer1/ppc_plot_jer1_hosp.png",ppc_plot_jer1_hosp,width = 23.05,height = 17.57,units="cm", bg = "white")


y_rep_mort=fit_jer1$draws("y_mort_tilde")
y_rep_mort=as_draws_matrix(y_rep_mort)

ppc_plot_jer1_mort <- ppc_dens_overlay(json_data_jer1$y_mort,y_rep_mort[1:200,])

ggsave("./CC2/jer1/ppc_plot_jer1_mort.png",ppc_plot_jer1_mort,width = 23.05,height = 17.57,units="cm",bg="white")


###########################
### mcmc intervals jer1 ###
###########################

intervals_jer1=read_cmdstan_csv(files = c("./CC2/jer1/jer1_1.csv","./CC2/jer1/jer1_2.csv","./CC2/jer1/jer1_3.csv"))
#int_jer1_post=as_draws_matrix(intervals_jer1$post_warmup_draws)
int_jer1_post=as_draws_df(intervals_jer1$post_warmup_draws)

mu_l_intervals_jer1 = mcmc_intervals(int_jer1_post,regex_pars =  "mu_l\\W")+
  ggplot2::labs( x="Log Hazard Ratio" 
                 #title = "Mu_l Jer1"
  ) + 
  scale_y_discrete(labels=rev(levels(mdat$ENTIDAD_UM)), limits = rev)

#int_jer1_post_ml=data.frame(int_jer1_post[,55:86])
#colnames(int_jer1_post_ml)=c(levels(mdat$ENTIDAD_UM))
#mu_l_intervals_jer1 <- mcmc_intervals(int_jer1_post_ml,regex_pars = (levels(mdat$ENTIDAD_UM)))+
#  ggplot2::labs( x="log hazard ratio", title = "Mu_l Jer1")
ggsave("./CC2/jer1/mu_1_intervalsjer1.png",mu_l_intervals_jer1,width = 23.05,height = 17.57,units="cm",bg="white")


###########################
### Beta intervals jer1 ###
###########################

beta_m_jer1=fit_jer1$draws("beta",format="df")

out_all_beta_m_jer1 = beta_m_jer1 %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_intervals_jer1 = mcmc_intervals(exp(-beta_m_jer1),regex_pars = "beta",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta[1]"="Diabetes",
             "beta[2]"="COPD",
             "beta[3]"="Obesity",
             "beta[4]"="Hypertension",
             "beta[5]"="Female",
             "beta[6]"="Chronic Kidney",
             "beta[7]"="Age",
             "beta[8]"="Semaforo",
             "beta[9]"="Diabetes : obesity",
             "beta[10]"="Diabetes : Hypertension",
             "beta[11]"="Obesity : Hypertension",
             "beta[12]"="Diabetes : Obesity : Hypertension"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.74,1.5)) +
  geom_text(
    data = out_all_beta_m_jer1,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.5),
    hjust = "inward"
  )

ggsave("./CC2/jer1/beta_intervalsjer1.png",beta_intervals_jer1,width = 23.05,height = 17.57,units="cm",bg="white")


#x_hosp=model.matrix(~EPOC+OBESIDAD+RENAL_CRONICA+ASMA+INMUSUPR+SEXO+EDAD,data=hdat)

beta_h_m_jer1=as_draws_df(fit_jer1$draws("beta_h"))

out_all_beta_h_m_jer1 = beta_h_m_jer1 %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_h_intervals_jer1 = mcmc_intervals(exp(-beta_h_m_jer1),regex_pars = "beta_h",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta_h[1]"="COPD",
             "beta_h[2]"="Obesity",
             "beta_h[3]"="Chronic Kidney",
             "beta_h[4]"="Asthma",
             "beta_h[5]"="Immunosuppression",
             "beta_h[6]"="Female",
             "beta_h[7]"="Age",
             "beta_h[8]"="Semaforo"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.9,1.3)) +
  geom_text(
    data = out_all_beta_h_m_jer1,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.3),
    hjust = "inward"
  )

ggsave("./CC2/jer1/beta_h_intervalsjer1.png",beta_h_intervals_jer1,width = 23.05,height = 17.57,units="cm",bg = "white")


################
### loo jer1 ###
################

#loo_hosp_jer1=loo(fit_jer1$draws("log_lik_hosp"), r_eff = NA)

loo_mort_jer1=loo(fit_jer1$draws("log_lik_mort"), r_eff = NA)
#saveRDS(loo_mort_jer1,"./CC2/jer1/loo_mort_jer1.rds")


##############
### sinjer ###
##############

mod_sinjer <- cmdstan_model("./CC2/sinjer/ModeloQR_quant.stan")

json_data_sinjer <- fromJSON(file="./Cmdstan/sin_jer.json")

fit_sinjer<- mod_sinjer$generate_quantities(c("./CC2/sinjer/sin_jer_1.csv","./CC2/sinjer/sin_jer_2.csv",
                                              "./CC2/sinjer/sin_jer_3.csv"), data = "./Cmdstan/sin_jer.json",  
                                            parallel_chains = 3)


########################
### plots ppc sinjer ###
########################

y_rep_hosp=fit_sinjer$draws("y_hosp_tilde")
y_rep_hosp=as_draws_matrix(y_rep_hosp)

ppc_plot_sinjer_hosp <- ppc_dens_overlay(json_data_sinjer$y_hosp,y_rep_hosp[1:200,])

ggsave("./CC2/sinjer/ppc_plot_sinjer_hosp.png",ppc_plot_sinjer_hosp,width = 23.05,height = 17.57,units="cm", bg = "white")


y_rep_mort=fit_sinjer$draws("y_mort_tilde")
y_rep_mort=as_draws_matrix(y_rep_mort)

ppc_plot_sinjer_mort <- ppc_dens_overlay(json_data_sinjer$y_mort,y_rep_mort[1:200,])

ggsave("./CC2/sinjer/ppc_plot_sinjer_mort.png",ppc_plot_sinjer_mort,width = 23.05,height = 17.57,units="cm", bg = "white")


#############################
### mcmc intervals sinjer ###
#############################

#intervals_sinjer=read_cmdstan_csv(files = c("./CC2/sinjer/sin_jer_1.csv","./CC2/sinjer/sin_jer_2.csv",
#                                            "./CC2/sinjer/sin_jer_3.csv"))
#int_sinjer_post=as_draws_df(intervals_sinjer$post_warmup_draws)

#############################
### Beta intervals sinjer ###
#############################

beta_m_sinjer=fit_sinjer$draws("beta",format="df")

out_all_beta_m_sinjer = beta_m_sinjer %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_intervals_sinjer = mcmc_intervals(exp(-beta_m_sinjer),regex_pars = "beta",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta[1]"="Diabetes",
             "beta[2]"="COPD",
             "beta[3]"="Obesity",
             "beta[4]"="Hypertension",
             "beta[5]"="Female",
             "beta[6]"="Chronic Kidney",
             "beta[7]"="Age",
             "beta[8]"="Semaforo",
             "beta[9]"="Diabetes : obesity",
             "beta[10]"="Diabetes : Hypertension",
             "beta[11]"="Obesity : Hypertension",
             "beta[12]"="Diabetes : Obesity : Hypertension"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.74,1.5)) +
  geom_text(
    data = out_all_beta_m_sinjer,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.5),
    hjust = "inward"
  )

ggsave("./CC2/sinjer/beta_intervalssinjer.png",beta_intervals_sinjer,width = 23.05,height = 17.57,units="cm",bg="white")


#x_hosp=model.matrix(~EPOC+OBESIDAD+RENAL_CRONICA+ASMA+INMUSUPR+SEXO+EDAD,data=hdat)

beta_h_m_sinjer=as_draws_df(fit_sinjer$draws("beta_h"))

out_all_beta_h_m_sinjer = beta_h_m_sinjer %>%
  pivot_longer(cols=-c(".chain",".iteration",".draw"),names_to = "index_beta",values_to = "Value") %>%
  mutate(Value=exp(-Value)) %>%
  group_by(index_beta) %>% median_qi(Value) %>% mutate_if(is.numeric, round, 2)

beta_h_intervals_sinjer = mcmc_intervals(exp(-beta_h_m_sinjer),regex_pars = "beta_h",prob_outer = .95) +
  ggplot2::labs( x="Hazard Ratio",
                 y="Comorbidity"
                 #,title = "DS Jer2"
  ) +
  scale_y_discrete(#labels=rev(c(colnames(x[,-1]))),
    labels=c("beta_h[1]"="COPD",
             "beta_h[2]"="Obesity",
             "beta_h[3]"="Chronic Kidney",
             "beta_h[4]"="Asthma",
             "beta_h[5]"="Immunosuppression",
             "beta_h[6]"="Female",
             "beta_h[7]"="Age",
             "beta_h[8]"="Semaforo"
    ),
    limits=rev)+
  geom_vline(xintercept = 1,lty="dashed",alpha=.3) +
  xlim(c(.9,1.3)) +
  geom_text(
    data = out_all_beta_h_m_sinjer,
    aes(y= index_beta,label = str_glue("[{Value}, {.lower} - {.upper}]"), x = 1.3),
    hjust = "inward"
  )

ggsave("./CC2/sinjer/beta_h_intervalssinjer.png",beta_h_intervals_sinjer,width = 23.05,height = 17.57,units="cm",bg = "white")


##################
### loo sinjer ###
##################

#loo_hosp_sinjer=loo(fit_sinjer$draws("log_lik_hosp"), r_eff = NA)

loo_mort_sinjer=loo(fit_sinjer$draws("log_lik_mort"), r_eff = NA)
#saveRDS(loo_mort_sinjer,"./CC2/sinjer/loo_mort_sinjer.rds")

# loo_hosp_jer2modi=readRDS("./CC2/jer2modi/loo_hosp_jer2modi.rds")
# loo_hosp_jer2=readRDS("./CC2/jer2/loo_hosp_jer2.rds")
# loo_hosp_jer1=readRDS("./CC2/jer2/loo_hosp_jer1.rds")
# loo_hosp_sinjer=readRDS("./CC2/jer2/loo_hosp_jer1.rds")

# loo_mort_jer2modi=readRDS("./CC2/jer2modi/loo_mort_jer2modi.rds")
# loo_mort_jer2=readRDS("./CC2/jer2/loo_mort_jer2.rds")
# loo_mort_jer1=readRDS("./CC2/jer1/loo_mort_jer1.rds")
# loo_mort_sinjer=readRDS("./CC2/sinjer/loo_mort_sinjer.rds")


loo=loo_compare(loo_mort_jer2modi,loo_mort_jer2,loo_mort_jer1,loo_mort_sinjer)
loo=as.data.frame(loo)
rownames(loo)=c("jer2modi", "jer2", "jer1", "sinjer")
write.csv(loo, file="./CC2/loo_comp.csv",row.names = T)
#el modelo jer2modi dice ser peorsito que el jer2
#loo_compare(loo_hosp_jer2modi,loo_hosp_jer2,loo_hosp_jer1,loo_hosp_sinjer)
#aqui jer2modi es el peor
