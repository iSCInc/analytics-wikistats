#!/bin/bash
ulimit -v 4000000

wikistats=/a/wikistats_git
squids=$wikistats/squids
perl=$squids/perl
csv=$squids/csv

cd $perl

perl SquidTraceUniqueImages.pl -i $csv -o $csv/uniques -d 30 
