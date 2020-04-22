FROM rocker/tidyverse

WORKDIR /home/fr_covidata_engine

RUN apt update -y && apt install -y libcurl4-openssl-dev

# install necessary libraries
RUN R -e "install.packages(c('tidyverse', 'sendmailR', 'dotenv', 'REDCapR', 'RCurl', 'checkmate', 'openxlsx'))"

ADD load*.R /home/fr_covidata_engine/
ADD functions.R /home/fr_covidata_engine/

# Note where we are and what is there
CMD pwd && ls -AlhF ./
