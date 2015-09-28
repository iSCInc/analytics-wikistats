#!/bin/bash

c1()(set -o pipefail;"$@" | perl -pe 's/.*/\e[1;32m$&\e[0m/g') # colorize output green 
c2()(set -o pipefail;"$@" | perl -pe 's/.*/\e[1;33m$&\e[0m/g') # colorize output yellow 

ulimit -v 400000

set -e 
set -o pipefail

wikistats=/a/wikistats_git
analytics=$wikistats/analytics
perl=$analytics/perl
perl=/home/ezachte/wikistats/analytics/perl # tests
csv_ez=/home/ezachte/wikistats/analytics/csv  # rc for report card
csv_rc=$analytics/csv  # rc for report card
csv_dumps=$wikistats/dumps/csv 
# unmerged=-u # uncomment to use legacy method of counting editors (unmerged, excluding commons)

clear

# Prepare several csv files, ready for importing into analytics database / front-end (e.g. LIMN)
# All generated files have _in_ in name signalling these contain data ready for importing into database / front-end

# www.walkernews.net/2007/06/03/date-arithmetic-in-linux-shell-scripts
yyyymm=$(date -d "1 month ago" +"%Y-%m")
yyyymm2=$(date -d "2 month ago" +"%Y-%m")
#yyyymm=2012-08 # !!!!!!  yyyymm "1 month ago" on 31 July gives 2012-07 !!!1 

#hard coded until auto set is more robust (day 21-31 use previous month, day 1-20 use two months ago)
yyyymm=2015-08 # last month to report on  
yyyymm2=2015-07 # previous month for comto compare 
yyyymm_rc=2015-10 # rc is month of RC meeting

echo process data up to $yyyymm and write to rc-$yyyymm.zip
log=$analytics/logs/prep_csv_$yyyymmdd.log 

set -x # show commands

mkdir -p $csv_rc/$yyyymm
rm -f $csv_rc/$yyyymm/comparison* 

cd $perl

# AnalyticsPrepComscoreData.pl scans /a/analytics/comscore for newest comScore csv files (with data for last 14 months) 
# parses those csv files, adds/replaces data from these csv files into master files (containing full history)
# and generates input csv file analytics_in_comscore.csv ready for importing
#
# note : these csv files were manually downloaded from http://mymetrix.comscore.com/app/report.aspx 
# and given more descriptive names, script finds newest files based on partial name search 
#
# -r replace (default is add only)
# -i input folder, contains manually downloaded csv files from comScore (or xls files manually converted to csv) 
# -m master files with full history
# -o output csv file, with reach per region, UV's per region and UV's per top web property, ready for import

# perl AnalyticsPrepComscoreData.pl -r -i $csv_rc/comscore -m /a/wikistats_git/analytics/csv/history -o $csv_rc | tee -a $log | cat
#c1 perl AnalyticsPrepComscoreData.pl -r -i $csv_rc/comscore -m /a/wikistats_git/analytics/csv/history -o $csv_rc/$yyyymm | tee -a $log | cat
c1 perl AnalyticsPrepComscoreData.pl -r -i $csv_ez/comscore -m /a/wikistats_git/analytics/csv/history -o $csv_rc/$yyyymm | tee -a $log | cat

# AnalyticsPrepBinariesData.pl read counts for binaries which were generated by wikistats 
# and which reside in /a/wikistats/csv_[project code]/StatisticsPerBinariesExtension.csv
# It filters and reorganizes data and produces analytics_in_binaries.csv
# Output csv contains: project code, language, month, extension name, count

c1 perl AnalyticsPrepBinariesData.pl -i $csv_dumps -o $csv_rc/$yyyymm | tee $log | cat

# AnalyticsPrepWikiCountsOutput.pl reads a plethora of fields from several csv files from wikistats process
# - It filters and reorganizes data and produces analytics_in_wikistats.csv, ready for import 

c1 perl AnalyticsPrepWikiCountsOutputMisc.pl -i $csv_dumps -o $csv_rc/$yyyymm -m $yyyymm           | tee -a $log | cat
c1 perl AnalyticsPrepWikiCountsOutputCore.pl -i $csv_dumps -o $csv_rc/$yyyymm -m $yyyymm $unmerged | tee -a $log | cat

# analytics_in_page_views.csv is written daily as part of WikiCountsSummarizeProjectCounts.pl 
# part of (/home/ezachte/pageviews_monthly.sh job) 
# which processes hourly projectcounts files (per wiki page view totals for one hour) from http://dammit.lt/wikistats
# and generates several files on different aggregation levels
# only action here is to copy data to this folder to have everything in one place
# note: unlike folder name suggests this file contains stats for all projects


cp $csv_dumps/csv_wp/analytics_in_page_views.csv $csv_rc/$yyyymm # adjust to wikistat_git when dump process has been migrated
cp $csv_dumps/csv_wp/wikilytics_in_pageviews.csv $csv_rc/$yyyymm # adjust to wikistat_git when dump process has been migrated

#echo compare csv files from folders $yyyymm2 and $yyyymm
#c2 perl AnalyticsCompareMonthlyCsvFiles.pl -c $csv_rc -1 $yyyymm -2 $yyyymm2 -t 2 -f wikilytics_in_pageviews.csv 
#c2 perl AnalyticsCompareMonthlyCsvFiles.pl -c $csv_rc -1 $yyyymm -2 $yyyymm2 -t 2 -f wikilytics_in_wikistats_core_metrics.csv

# set +x # do not show commands

echo "zip -> $csv_rc/$yyyymm"
cd $csv_rc/$yyyymm
zip rc-$yyyymm_rc.zip wikilytics*.csv # comparison*.txt
ls -l

echo -e "\n>>> ready <<<"
