#!/usr/bin/perl

  $wikistats             = "/a/wikistats_git" ;
  $squids                = "$wikistats/squids" ;
  $cfg_liblocation       = "$squids/perl" ;
  $cfg_liblocation       = "/home/ezachte/wikistats/squids-scripts-2012-10/perl" ; # temp

  $cfg_path_csv          = "$squids/csv" ;
  $cfg_path_reports      = "$squids/reports" ;
  $cfg_path_log          = "$squids/logs" ;

  $cfg_path_csv_test     = "W:/# Out Locke" ;      # Erik
  $cfg_path_reports_test = "W:/# Out Test/Locke" ; # Erik
  $cfg_path_log_test     = "W:/# Out Test/Locke" ; # Erik
# $cfg_path_csv_test     = "/srv/erik/" ;          # Andr�
# $cfg_path_reports_test = "/srv/erik/" ;          # Andr�
# $cfg_path_log_test     = "/srv/erik/" ;          # Andr�

# set default arguments for test on local machine
  $cfg_default_argv = "-m 2011-08" ;   # monthly report
# $cfg_default_argv = "-w" ;           # refresh country info from Wikipedia (population etc)
# $cfg_default_argv = "-c" ;           # country/regional reports
# $cfg_default_argv = "-c -q 2011Q4" ; # country/regional reports based on data for one quarter only
