#!/bin/sh

echo_() {
echo report=$report
  echo "$1" | tee -a $logfile| cat
}

yyyymmdd=$(date +"%Y_%m_%d")

htdocs=thorium.eqiad.wmnet::srv/stats.wikimedia.org/htdocs/ ; echo_ htdocs=$htdocs

scripts=$WIKISTATS_SCRIPTS                              ; echo_ scripts=$scripts
perl_dumps=$scripts/dumps/perl                          ; echo_ perl_dumps=$perl_dumps
perl_dammit=$scripts/dammit.lt/perl                     ; echo_ perl_dammit=$perl_dammit

data_dumps=$WIKISTATS_DATA/dumps                        ; echo_ data_dumps=$data_dumps
data_dammit=$WIKISTATS_DATA/dammit                      ; echo_ data_dammit=$data_dammit
projectcounts=$data_dammit/projectcounts                ; echo_ projectcounts=$projectcounts
projectviews=$data_dammit/projectviews                  ; echo_ projectviews=$projectviews 
csv=$data_dumps/csv                                     ; echo_ csv=$csv
csv_in=$data_dumps/csv                                  ; echo_ csv_in=$csv_in
csv_pv=$data_dammit/projectviews/csv                    ; echo_ csv_pv=$csv_pv
out=$data_dumps/out
meta=$csv_in/csv_mw/MetaLanguages.csv                   ; echo_ meta=$meta

logfile=$data_dumps/logs/pageviews_monthly/log_projectviews_monthly_$yyyymmdd.txt  ; echo_ logfile=$logfile
report=$data_dumps/logs/pageviews_monthly/log_pageviews_monthly_$yyyymmdd.txt  ; echo_ report=$report

date_switch="201504" # not used now , hard coded in perl file 

echo "**************************" | tee -a $report | cat
echo "Start pageviews_monthly.sh" | tee -a $report | cat
echo "**************************" | tee -a $report | cat

# step 0: collect list of valid projects/languages 
list=WhiteListWikis.csv
cd $csv_in
cat csv_wb/$list csv_wk/$list csv_wn/$list csv_wo/$list csv_wp/$list csv_wq/$list  csv_ws/$list csv_wv/$list csv_wx/$list > $projectcounts/$list

# step 1: data collecting 
# *************************************************************************************************************************************************
# Main steps in WikiCountsSummarizeProjectCounts.pl:

# LogArguments 
# ParseArguments 
# SetComparisonPeriods 
# InitProjectNames 
# ScanWhiteList 
# ScanTarFiles  
# FindMissingFiles 
# CountPageViews 
# AdjustForMissingFilesAndUndercountedMonths 
# WriteCsvFilesPerPeriod ($no_normalize)        (-> files X)               
# WriteCsvHtmlFilesPopularWikis ($no_normalize) (-> files Y) 
# normalize counts to 30 day months
# WriteCsvFilesPerPeriod ($normalize)           (-> files X)
# WriteCsvHtmlFilesPopularWikis ($normalize)    (-> files Y)


# Input:
# $projectcounts/WhiteListWikis.csv          <- list of valid projects/languages, based on dumps found, see step 0 (perl sub ScanWhiteList)
# $projectcounts/projectcounts-[yyyy].tar    <- sanitized and tarred version of hourly views per wiki, since 2008  (perl sub ScanTarFiles)
#                                            source: webstatscollector
#                                            updated daily by /home/ezachte/wikistats/dammit.lt/bash/dammit_sync.sh
#                                            from /mnt/data/xmldatadumps/public/other/pagecounts-raw/yyyy/yyyy-mm/projectcounts*
#
#                                            for some months with big data loss, due to server overload, projectcounts files have been repaired,
#                                              inferring amount of loss from gaps between sequence numbers
#                                            also some date ranges are skipped on purpose, because data are known to be unreliable/incomplete,
#                                              missing data will be compensated in AdjustforMissingFilesAndUndercountedMonths

# Output: (*) 
# X: $csv/csv_wp/analytics_in_page_views.csv                         -> <- intermediate file, read back in immediately after generation
# X: $csv/csv_wp/analytics_chk_page_views_totals_normalized.csv
# X: $csv/csv_[project]/PageViewsPer[$period][All][Normalized].csv 
#    $period=[Hour/Day/Week/Weekday/Month]                           -> used for ad hoc analysis, not in regular reports, except monthly version,
#                                                                        daily job /home/ezachte/wikistats/dumps/bash/pageviews_monthly.sh updates all reports
#                                                                        listed at http://stats.wikimedia.org/EN/TablesPageViewsSitemap.htm from 
#                                                                        ../PageViewsPerMonth[All][Normalized].csv

# Y: $csv/csv_wp/PageViewsPerMonthPopularWikis[Normalized].csv       -> old Report Card, 36 months history for largest wikis and projects
# Y: $csv/csv_wp/wikilytics_in_pageviews.csv                         -> new Report Card, copy from previous file, for name consistency
#                                                                         contains series of monthly page views since July 2008 (mobile since June 2010)  
#                                                                         series are: combined / non-mobile / mobile for 25 most visited wikis, 
#                                                                         followed by similar series with totals on project level (Wikipedia, Wiktionary, etc)
   
# Y: $csv/csv_wp/PageViewsMoversShakersPopularWikis[Normalized]_yyyy_mm.html (**) 
#                                                                    -> old Report Card, html code included directly into table 'movers and shakers' (M&S) 
#                                                                       see e.g. http://stats.wikimedia.org/reportcard/RC_2012_02_detailed.html#fragment-26 


# ad processing subs
# sub FindMissingFiles: find out for which days/hours input is missing (to recalc monthly totals in next step)
# sub CountPageViews: aggregate hourly counts into daily/weekly/weekday/monthly counts and report anomalies
# sub AdjustForMissingFilesAndUndercountedMonths: recalc monthly totals by extrapolating from incomplete counts

# *  = some csv files which contain input for all projects have historically been stored in csv/csv_wp (some day move these to csv/csv_mw)
# ** = yep not csv really, despite folder name csv_.. ;)
# *************************************************************************************************************************************************

# old version before upgrade to wc 3.0 format:
# perl $perl/WikiCountsSummarizeProjectCounts.pl -i $projectcounts -o $csv -w $projectcounts -m $meta| tee -a $report | cat

# -i = input folder (with 'wc1' tar files = webstatscollector 1 = with legacy page view definition = a.o. without bots removed) 
# -j = input folder (with 'wc3' tar files = webstatscollector 3 = new page view definition         = a.o. with bots removed)
# -m = meta file with data per language code (language name, number of speakers, regions)
# -o = output (csv files)
# -s = start month for new page view definition (not used, hard coded = 201505)
# -w = folder for WhiteListWikis.csv (valid language codes)

cd $projectviews
perl $perl_dammit/DammitSummarizeProjectViews.pl -i $projectcounts -j $projectviews -o $csv_pv -w $projectcounts -m $meta -s $date_switch | tee $logfile | cat
zip projectviews_csv.zip csv/csv*/projectviews_* log*projectviews*
rsync -av -ipv4 projectviews_csv.zip  dataset1001.wikimedia.org::pagecounts-ez/projectviews

# exit # tests only 

# -l = language (en:English)
# -m = mode (wb:wikibooks, wk:wiktionary, wn:wikinews, wp:wikipedia, wq:wikiquote, ws:wikisource, wv:wikiversity, wx:wikispecial=commons,meta,..)
# -i = input folder
# -i = input folder
# -j = folder for projectviews csv files
# -n = normalized (all months -> 30 days)
# -r = region
# -v = views (n:non-mobile, m:mobile, c:combined)
# -s = source (s:squids, d:dammit) for page views only -s d = default

echo report=$report
date | tee -a $report | cat
cd $perl_dumps 

perl WikiReports.pl -v n -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n | tee -a $report | cat 
perl WikiReports.pl -v n -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp    | tee -a $report | cat
perl WikiReports.pl -v m -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n | tee -a $report | cat 
perl WikiReports.pl -v m -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp    | tee -a $report | cat 
perl WikiReports.pl -v c -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n | tee -a $report | cat 
perl WikiReports.pl -v c -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp    | tee -a $report | cat 
echo "rsync -av $out/out_wp/EN/TablesPageViewsMonthly*.htm  $htdocs/EN"             | tee -a $report | cat
      rsync -av $out/out_wp/EN/TablesPageViewsMonthly*.htm  $htdocs/EN              | tee -a $report | cat

perl WikiReports.pl -v n -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v n -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
perl WikiReports.pl -v m -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v m -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
perl WikiReports.pl -v c -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v c -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
echo "rsync -av $out/out_wn/EN/TablesPageViewsMonthly*.htm  $htdocs/wikinews/EN"    | tee -a $report | cat
      rsync -av $out/out_wn/EN/TablesPageViewsMonthly*.htm  $htdocs/wikinews/EN     | tee -a $report | cat

perl WikiReports.pl -v n -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx -n | tee -a $report | cat
perl WikiReports.pl -v n -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx    | tee -a $report | cat
perl WikiReports.pl -v m -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx -n | tee -a $report | cat
perl WikiReports.pl -v m -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx    | tee -a $report | cat
perl WikiReports.pl -v c -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx -n | tee -a $report | cat
perl WikiReports.pl -v c -m wx -l en -i $csv/csv_wx/ -j $csv_pv/csv_wx -o $out/out_wx    | tee -a $report | cat
echo "rsync -av $out/out_wx/EN/TablesPageViewsMonthly*.htm  $htdocs/wikispecial/EN" | tee -a $report | cat
      rsync -av $out/out_wx/EN/TablesPageViewsMonthly*.htm  $htdocs/wikispecial/EN  | tee -a $report | cat

perl WikiReports.pl -v n -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb -n | tee -a $report | cat
perl WikiReports.pl -v n -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb    | tee -a $report | cat
perl WikiReports.pl -v m -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb -n | tee -a $report | cat
perl WikiReports.pl -v m -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb    | tee -a $report | cat
perl WikiReports.pl -v c -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb -n | tee -a $report | cat
perl WikiReports.pl -v c -m wb -l en -i $csv/csv_wb/ -j $csv_pv/csv_wb -o $out/out_wb    | tee -a $report | cat
echo "rsync -av $out/out_wb/EN/TablesPageViewsMonthly*.htm  $htdocs/wikibooks/EN"   | tee -a $report | cat
      rsync -av $out/out_wb/EN/TablesPageViewsMonthly*.htm  $htdocs/wikibooks/EN    | tee -a $report | cat

perl WikiReports.pl -v n -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk -n | tee -a $report | cat
perl WikiReports.pl -v n -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk    | tee -a $report | cat
perl WikiReports.pl -v m -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk -n | tee -a $report | cat
perl WikiReports.pl -v m -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk    | tee -a $report | cat
perl WikiReports.pl -v c -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk -n | tee -a $report | cat
perl WikiReports.pl -v c -m wk -l en -i $csv/csv_wk/ -j $csv_pv/csv_wk -o $out/out_wk    | tee -a $report | cat
echo "rsync -av $out/out_wk/EN/TablesPageViewsMonthly*.htm  $htdocs/wiktionary/EN"  | tee -a $report | cat
      rsync -av $out/out_wk/EN/TablesPageViewsMonthly*.htm  $htdocs/wiktionary/EN   | tee -a $report | cat

perl WikiReports.pl -v n -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v n -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
perl WikiReports.pl -v m -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v m -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
perl WikiReports.pl -v c -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn -n | tee -a $report | cat
perl WikiReports.pl -v c -m wn -l en -i $csv/csv_wn/ -j $csv_pv/csv_wn -o $out/out_wn    | tee -a $report | cat
echo "rsync -av $out/out_wn/EN/TablesPageViewsMonthly*.htm  $htdocs/wikinews/EN"    | tee -a $report | cat
      rsync -av $out/out_wn/EN/TablesPageViewsMonthly*.htm  $htdocs/wikinews/EN     | tee -a $report | cat

perl WikiReports.pl -v n -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo -n | tee -a $report | cat
perl WikiReports.pl -v n -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo    | tee -a $report | cat
perl WikiReports.pl -v m -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo -n | tee -a $report | cat
perl WikiReports.pl -v m -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo    | tee -a $report | cat
perl WikiReports.pl -v c -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo -n | tee -a $report | cat
perl WikiReports.pl -v c -m wo -l en -i $csv/csv_wo/ -j $csv_pv/csv_wo -o $out/out_wo    | tee -a $report | cat
echo "rsync -av $out/out_wo/EN/TablesPageViewsMonthly*.htm  $htdocs/wikivoyage/EN"  | tee -a $report | cat
      rsync -av $out/out_wo/EN/TablesPageViewsMonthly*.htm  $htdocs/wikivoyage/EN   | tee -a $report | cat

perl WikiReports.pl -v n -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq -n | tee -a $report | cat
perl WikiReports.pl -v n -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq    | tee -a $report | cat
perl WikiReports.pl -v m -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq -n | tee -a $report | cat
perl WikiReports.pl -v m -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq    | tee -a $report | cat
perl WikiReports.pl -v c -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq -n | tee -a $report | cat
perl WikiReports.pl -v c -m wq -l en -i $csv/csv_wq/ -j $csv_pv/csv_wq -o $out/out_wq    | tee -a $report | cat
echo "rsync -av $out/out_wq/EN/TablesPageViewsMonthly*.htm  $htdocs/wikiquote/EN"   | tee -a $report | cat
      rsync -av $out/out_wq/EN/TablesPageViewsMonthly*.htm  $htdocs/wikiquote/EN    | tee -a $report | cat

perl WikiReports.pl -v n -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws -n | tee -a $report | cat
perl WikiReports.pl -v n -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws    | tee -a $report | cat
perl WikiReports.pl -v m -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws -n | tee -a $report | cat
perl WikiReports.pl -v m -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws    | tee -a $report | cat
perl WikiReports.pl -v c -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws -n | tee -a $report | cat
perl WikiReports.pl -v c -m ws -l en -i $csv/csv_ws/ -j $csv_pv/csv_ws -o $out/out_ws    | tee -a $report | cat
echo "rsync -av $out/out_ws/EN/TablesPageViewsMonthly*.htm  $htdocs/wikisource/EN"  | tee -a $report | cat
      rsync -av $out/out_ws/EN/TablesPageViewsMonthly*.htm  $htdocs/wikisource/EN   | tee -a $report | cat

perl WikiReports.pl -v n -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv -n | tee -a $report | cat
perl WikiReports.pl -v n -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv    | tee -a $report | cat
perl WikiReports.pl -v m -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv -n | tee -a $report | cat
perl WikiReports.pl -v m -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv    | tee -a $report | cat
perl WikiReports.pl -v c -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv -n | tee -a $report | cat
perl WikiReports.pl -v c -m wv -l en -i $csv/csv_wv/ -j $csv_pv/csv_wv -o $out/out_wv    | tee -a $report | cat
echo "rsync -av $out/out_wv/EN/TablesPageViewsMonthly*.htm  $htdocs/wikiversity/EN" | tee -a $report | cat
      rsync -av $out/out_wv/EN/TablesPageViewsMonthly*.htm  $htdocs/wikiversity/EN  | tee -a $report | cat

# publish regional reports 
# for region in artificial  
for region in africa asia america europe india oceania artificial 
do
  perl WikiReports.pl -v n -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n  -r $region | tee -a $report | cat ; 
  perl WikiReports.pl -v n -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp     -r $region | tee -a $report | cat ; 
  perl WikiReports.pl -v m -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n  -r $region | tee -a $report | cat ; 
  perl WikiReports.pl -v m -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp     -r $region | tee -a $report | cat ;
  perl WikiReports.pl -v c -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp -n  -r $region | tee -a $report | cat ; 
  perl WikiReports.pl -v c -m wp -l en -i $csv/csv_wp/ -j $csv_pv/csv_wp -o $out/out_wp     -r $region | tee -a $report | cat ;
done;
for region in Africa Asia America Europe India Oceania Artificial 
do	
  echo "rsync -av $out/out_wp/EN_$region/TablesPageViewsMonthly*.htm  $htdocs/EN_$region" | tee -a $report | cat
        rsync -av $out/out_wp/EN_$region/TablesPageViewsMonthly*.htm  $htdocs/EN_$region  | tee -a $report | cat 
done;

# report per project, non mobile site (arg '-v n' = views non-mobile)
# raw/normalized (with/without arg '-n') 
# non-mobile site/mobile site/combined (arg '-v n/m/c')

# report for Wikipedia mobile site, based on squids log (arg '-v m' = views mobile)
cp $csv/csv_wp/LanguageNames*.csv $csv/csv_sp # up to date language names from php sources and Wikipedia
cp $csv/csv_wp/PageViewsPerMonthAll.csv $csv/csv_sp/PageViewsPerMonthAllCombi.csv # base sort order on non-mobile pageviews

# Stefan Petrea's squid log based reports are now obsolete, after switch to webstatscollector 3.0  
# perl WikiReports.pl -v m -m wp -l en -q -i $csv/csv_sp/ -j $csv/csv_sp -o $out/out_sp -n | tee -a $report | cat
# perl WikiReports.pl -v m -m wp -l en -q -i $csv/csv_sp/ -j $csv/csv_sp -o $out/out_sp    | tee -a $report | cat
#       rsync -av $out/out_sp/EN/TablesPageViewsMonthlySquidsMobile.htm          $htdocs/wikimedia/squids/TablesPageViewsMonthlySquidsMobile.htm
#       rsync -av $out/out_sp/EN/TablesPageViewsMonthlySquidsOriginalMobile.htm  $htdocs/wikimedia/squids/TablesPageViewsMonthlySquidsOriginalMobile.htm

# zip and publish raw daily counts
cd $csv/csv_wp
zip PageViewsPerDayAll.csv.zip PageViewsPerDayAll.csv        | tee -a  $report | cat
rsync -av PageViewsPerDayAll.csv.zip $htdocs/archive/        | tee -a  $report | cat
rsync -av PageViewsPerMonthMobile* $htdocs/wikimedia/mobile/ | tee -a  $report | cat

echo "Ready" | tee -a $report | cat
date | tee -a $report | cat
