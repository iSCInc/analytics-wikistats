#!/usr/bin/perl

# About redirects:
# 1) namespace
# Only pages for certain namepaces are counted as proper 'articles'. Mostly namespace 0 but on some projects other namespaces qualify. (See sub NameSpaceArticle)
# 2) internal link
# Also pages without internal links do not qualify (on most projects).
# For stub dumps this can not be established: no raw text available, hence different page totals are found
# 3) redirect
# Also pages which are redirects do not qualify for article counts (but they do count for edit(or) counts starting Dec 2016).
# For stub dumps this can not be established per revisions (and thus different page totals are found over consecutive dumps)
# For full archive dumps (with all page content) the article content used to be for #REDIRECT, or a localized version, like so
# $revision_is_redirect = ($article =~ m/(?:$redirtag).*?\[\[.*?(?:\||\]\])/ios) ;
# For stub dumps the page xml can contain the following tag <redirect title="[some title]" />, but once per page, not per revision

$start = time ;

use CGI::Carp qw(fatalsToBrowser);
use Time::Local ;
use Getopt::Std ;
use Tie::File ; # http://perldoc.perl.org/Tie/File.html


$Kb = 1024 ;
$Mb = $Kb * $Kb ;

# to do : https://bugzilla.wikimedia.org/show_bug.cgi?id=33253
sub NameSpaceArticle
{
  my ($language, $namespace) = @_ ;

  if ($base_content_namespaces_on_api)
  { 
    if (! $namespaces_initialized) 
    { abort "NameSpaceArticle: content_namespaces not initialized" ; }

    return ($content_namespace {$namespace} != 0 ) ;
  }
  else 
  {
  # if changed, also change WikiReportsOutputTables, find in code string 'NameSpaceArticle'
    if ($language eq 'strategy')
    { return (($namespace == 0) || ($namespace == 106)) ; }
    elsif ($language eq 'commons')
  # { return (($namespace == 0) || ($namespace == 6) || ($namespace == 14)) ; } # + file and category namespaces
    { return ($namespace == 6) ; } # Oct 2016 only binaries
    elsif ($mode_ws) # wikisource wikis
    { return (($namespace == 0) || ($namespace == 102) || ($namespace == 104) || ($namespace == 106)) ; } # + author, page, index (`100 = portal)
    else
    { return ($namespace == 0) ; }
  }  
}

sub ReadInputXml
{
  &TraceMem ;

  $ImageExtensions = "(gif|jpg|png|bmp|jpeg)";

  $cnt_titles         = -1 ;
  $cnt_users_reg      =  0 ; # increment with 2 for every unique registered user found
  $cnt_users_ip       =  1 ; # increment with 2 for every unique ip address found
  $cnt_inflate_errors = 0 ;

  $language_prev = $language ;
  $wikipedia = $wikipedias {$language} ;
  $wikipedia =~ s/^[^\s]+(.*)$/$1/ ;
  $language = "en" ;

  if ($use_tie)
  { &Log ("Threshold for RevisionsCached (Tie\:\:File): $threshold_tie_file\n") ; }

  &LogT ("\n===== Start reading input =====\n") ;

  open "FILE_EDITS_ARTICLES", ">", $file_csv_edits_per_article2 || abort ("Temp file '$file_csv_edits_per_article2' could not be opened.") ;
  open "FILE_CATEGORIES", ">", $file_categories || abort ("Perl file '$file_categories' could not be opened.") ;
  if ($dump2csv)
  { open "FILE_DUMP_CSV", ">", $file_dump_csv || abort ("Perl file '$file_dump_csv' could not be opened.") ; }

  open "FILE_CREATES", ">", $file_csv_creates || abort ("Perl file '$file_csv_creates' could not be opened.") ;
  print FILE_CREATES "# fields: article type,yyyymmddhhnn,namespace,usertype,user,userid,title,uploadwizard\n" ;
  print FILE_CREATES "# usertype  = [A:anonymous|B:bot|R:registered user]\n" ;
  print FILE_CREATES "# article type = [-:page contains no internal link|R:page is redirect|S:(link list, deprecated)|S:stub|+:normal article]\n" ;
  print FILE_CREATES "# when processing full archive dump: count article only when it contains an internal link (official article definition), and is not a redirect\n" ;
  print FILE_CREATES "# when processing full archive dump: only difference for stubs is : those are not counted for alternate article count \n" ;
  print FILE_CREATES "# when processing stub dump: article content is unavailable (no test for stub threshold) -> article count will be higher\n" ;

  if ($edits_only)
  { print FILE_CREATES "# this file was generated from stub dump\n" ; }
  else
  { print FILE_CREATES "# this file was generated from full archive dump\n" ; }

  if ($mode eq "wp")
  {
    open "FILE_TIMELINES",         ">", $file_csv_timelines         || abort ("Temp file '$file_csv_timelines' could not be opened.") ;
    open "FILE_TIMELINES_SKIPPED", ">", $file_csv_timelines_skipped || abort ("Temp file '$file_csv_timelines_skipped' could not be opened.") ;
  }

  $language = $language_prev ;

  $filesizelarge = ((-s $file_in_xml_full) > $threshold_filesize_large) ;
  if ($filesizelarge)
  { &LogT ("Large input file ( over " . int ($threshold_filesize_large/1000_000) . " Mb ) -> optimise memory usage aggresively\n") ; }
  else
  {
    $trace_on_exit = $false ;
    $trace_on_exit_concise = $true ;
  }

  $log_progress_verbose = $filesizelarge ;

  $prescan = $false ;
  if (($mode eq "wb") || ($mode eq "wv")) # prescan to collect book titles
  {
    $prescan = $true ;

    $timestart_parse = time ;
    &ReadFileXml ($file_in_xml_full) ;
    &LogT ("\n\nParsing xml file took " . ddhhmmss (time - $timestart_parse). ".\n") ;

    $prescan = $false ;
  }

  $timestart_parse = time ;
  &ReadFileXml ($file_in_xml_full) ;
  $time_parse_input = time - $timestart_parse ;

  &LogT ("===== Input read. Parsing xml file took " . ddhhmmss ($time_parse_input). " =====\n") ;
  
  close FILE_TIMELINES ;
  close FILE_TIMELINES_SKIPPED ;
  close FILE_EDITS_ARTICLES ;
  close FILE_CATEGORIES ;
  if ($dump2csv)
  { close FILE_DUMP_CSV ; }
  close FILE_CREATES ;

  if ($use_tie && ! $edits_only && ($size_rev_0_gt + $size_rev_0_eq > 0))
  { &LogT ("\nRevisions cached on $size_rev_0_gt / " . (($size_rev_0_gt + $size_rev_0_eq)/1000) . "K articles or " .
            sprintf ("%.3f", 100* ($size_rev_0_gt/($size_rev_0_gt + $size_rev_0_eq))) . "\%.\n") ; }

#  # @titles and @article_history are both huge arrays
#  # temporary file makes that they are not needed at same time

  if ($file_events_article_prev ne "")
  { close $file_events_article_prev ; }

  foreach $file (keys %files_events_month)
  { close $files_events_month {$file} ; }
  foreach $file (keys %files_events_user_month)
  { close $files_events_user_month {$file} ; }

# if ($forecast_partial_month)
# {
#   foreach $file (keys %files_events_user_month_partial)
#   { close @files_events_user_month_partial {$file} ; }
# }

  &TraceRelease ("Release table \%titles") ;
  undef (%titles) ;
  &TraceMem ;

  &TraceRelease ("Release table \%ndx_titles") ;
  undef (%ndx_titles) ;
  &TraceMem ;

  &LogQ ("\n") ;
  foreach $key (keys %undef_namespaces)
  { &LogQ ("False namespace " . sprintf ("%4d", $undef_namespaces {$key}) . "x : '$key'\n") ; }
  &Log ("\n") ;
  foreach $key (sort {$a <=> $b} keys %total_per_namespace)
  { &LogQ ("Pages per namespace '" . sprintf("%3d",$key) . "': " . $total_per_namespace {$key} . "x\n") ; }

  $line = "" ;
  foreach $key (sort {$imagetags {$b} <=> $imagetags {$a}} keys %imagetags)
  { $line .= $imagetags {$key} . " x $key, " ;  }
  $line =~ s/, $// ;
  if ($line eq '')
  { &LogT ("No image tags encountered\n") ; }
  else
  { &LogT ("Image tags encountered: $line\n\n") ; }

  if ($reverts_sha1_articles > 0)
  {
    &Log ("\n\n$reverts_sha1_articles_bots bot 'reverts' out of $reverts_sha1_articles SHA1 reverts = " .
          "-B: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_1 / $reverts_sha1_articles) .
          ", B-: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_2 / $reverts_sha1_articles) .
          ", BB: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_3 / $reverts_sha1_articles) .
          "\n\n") ;

    &LogT ("Revert flags found\n") ;
    foreach $key (sort keys %reverts_all)
    { &LogT ("$key: ${reverts_all{$key}}\n") ; }
    &Log ("\n") ;

    &LogT ("\n\nRevert delays:\n") ;
    foreach $yyyymm (sort keys %reverts_after_month)
    {
      my $avg_secs = sprintf ("%.0f", $reverts_after_month {$yyyymm} / $reverts_after_month_sha1 {$yyyymm}) ;
      my $avg_ddhhmmss = ddhhmmss ($avg_secs, "%2d d, %2d h, %2d m, %2ds") ;
      print "$yyyymm: $avg_ddhhmmss = ${reverts_after_month {$yyyymm}} secs / ${reverts_after_month_sha1 {$yyyymm}}\n" ;
    }
  }

# if ($events_written > 0)
# {
#   &LogT ("\nEvents written $events_written\n") ;
#    &LogT ("Revisions analysed in detail $articles_ne, analysis skipped on $articles_eq revisions.\n") ;
# }
# else
# { &LogT ("\nNo events written\n") ; }

  &Log ("\n") ;
}

sub ReadFileXml
{
  $file_in  = shift ;

  if (! -e $file_in)
  { abort ("ReadFileXml \$file_in '$file_in' not found.\n") ; }

  if ($file_in =~ /\.gz$/)
  {
    open FILE_IN, "-|", "gzip -dc \"$file_in\"" || abort ("Input file '" . $file_in . "' could not be opened.") ;
    $fileformat = "gz" ;
  }
  elsif ($file_in =~ /\.bz2$/)
  {
    open FILE_IN, "-|", "bzip2 -dc \"$file_in\"" || abort ("Input file '" . $file_in . "' could not be opened.") ;
    $fileformat = "bz2" ;
  }
  elsif ($file_in =~ /\.7z$/)
  {
    open FILE_IN, "-|", "7z e -so \"$file_in\"" || abort ("Input file '" . $file_in . "' could not be opened.") ;
    $fileformat = "7z" ;
  }
  else
  {
    open FILE_IN, "<", $file_in || abort ("Input file '" . $file_in . "' could not be opened.") ;
    $fileformat = $file_in ;
    $fileformat =~ s/^.*?\.([^\.]*)$/$1/ ;
  }

  binmode FILE_IN ;

  # log edits per user per month per namespace for this article, to be sorted and aggregated later
  if (! $prescan)
  {
    open    EDITS_USER_MONTH_NAMESPACE_LOG, ">", $file_csv_user_month_namespace_log ;
    binmode EDITS_USER_MONTH_NAMESPACE_LOG ;
  }

  open REVERTS_SAMPLE, ">", $file_csv_reverts_sample ;
  open REVERTED_EDITS, ">", $file_csv_reverted_edits ;

  print REVERTED_EDITS "# Sampling rate $reverts_sampling\n" ;
  print REVERTED_EDITS "# Fields for reverts only based on comment:\n" ;
  print REVERTED_EDITS "# yyyymm,flags,namespace,comment\n" ;
  print REVERTED_EDITS "# Fields for reverts detected by SHA1 comparisons:\n" ;
  print REVERTED_EDITS "# yyyymm,flags,namespace,*edits back,*x secs earlier,*flags,*title,*timestamp,*usertype,user,*user,comment\n" ;
  print REVERTED_EDITS "# * = for reverted revision (oldest if multiple)\n" ;
  print REVERTED_EDITS "# Flags:" ;
  print REVERTED_EDITS "# 1 N/- = article namespace (differs per wiki), often only namespace 0" ;
  print REVERTED_EDITS "# 2 C/- = comment contains revert text (e.g. revert/rv/undo (can differ per language)\n" ;
  print REVERTED_EDITS "# 3 M/X/- = reverted revision based on comparing SHA1 checksums (X: subsequent revisions, hence no change made, not a revert really)\n"  ;
  print REVERTED_EDITS "# 4 B/- = bot ($comment =~ /\brobot\b/i) || ($user =~ /conversion script/i) || ($user =~ /MediaWiki default/i)\n" ;
  print REVERTED_EDITS "# 5 B/- = bot (classified as bot based on bits in MySQL user table, either here or many other wikis (for small wikis with incomplete administration))\n" ;
  print REVERTED_EDITS "# 6 R/A/B = user type Registered user / Anonymous user / Bots (~ same as 5)\n" ;
  print REVERTED_EDITS "# 7 R/A/B/- = user type for restored revision (-: unknown (no sha1 revert)\n" ;
  print REVERTED_EDITS "# 8 S/- = self revert (all reverted revisions by same editor)\n" ;

  $filesize = -s $file_in ;
  $fileage  = -M $file_in ;
  $filesize_ondisk = $filesize ;

  if ($filesize == 0)
  { abort ("Input file " . $file_in . " is empty.") ; }

  &LogT ("\nUse temp dir '" . $path_temp . "\'\n") ;
  &LogT ("\n\nRead xml dump file \'" . $file_in . "\'\n\n") ;

  my $file_completely_parsed = $false ;
  $pages_read     = 0 ;
  $revisions_read = 0 ;
  $bytes_read = 0 ;
  $mb_read = 0 ;

  undef %namespaces ;

  &XmlReadUntil ('<mediawiki') ;
  if ($line !~ /<mediawiki/)
  { abort ("String '<mediawiki' not found at start of file '" . $file_in . "'. Incomplete or corrupt file? Filesize $filesize bytes. File age " . sprintf ("%.1f", $fileage) . " days.") ; }

  &ReadInputXmlNamespaces ;

  if ((($mode ne "wb") && ($mode ne "wv")) || $prescan)
  { &LogC ("size: " . &i2KbMb ($filesize). " prev run: $runtime_previous_run") ; }
  &LogT  ("File size: " . &i2KbMb ($filesize) . "\n") ;
  &LogT  ("Data read (Mb):\n") ;

#  if ($mb_read < 280000)
#  {
#    &LogT  ("Move fast ahead till 280000 Mb\n\n") ;

#    while ($line = <FILE_IN>)
#    {
#      $bytes_read += length ($line) ;
#      if ($lines_read_xml_read_until++ % 1000 == 0)
#      {
#        &XmlReadProgress ;
#        if ($mb_read > 280000)
#        {
#          &LogT  ("\n\nFast ahead complete\n\n") ;
#          last ;
#        }
#      }
#    }
#  }

  &XmlReadUntil ('(?:<page>|<\/mediawiki>)') ;
  while ($line =~ /<page>/)
  {
    $pages_read ++ ;
    my $start_readinputxmlpage = code_started() ;
    &ReadInputXmlPage ;
    code_complete ("ReadInputXmlPage", $start_readinputxmlpage) ;
    &XmlReadUntil ('(?:<page>|<\/mediawiki>)') ;

    if ($reverts_only && ($reverts_sampling > 1)) # only process every n th article to speed things up on
    {
       $reverts_sampling2 = $reverts_sampling ;
       while (($line =~ /<page>/) && (-- $reverts_sampling2 > 0))
       {
         $pages_read ++ ;
         &XmlReadUntil ('(?:<page>|<\/mediawiki>)') ;
       }
    }
  }

  $filesize_uncompressed = $bytes_read ;

  if ($line !~ /<\/mediawiki>/)
  { &XmlReadUntil ('<\/mediawiki>') ; }

  if ($line =~ /<\/mediawiki>/)
  { $file_completely_parsed = $true ; }

  if ($edits_only ) # temp: no-redirects file missed closing /mediawiki
  { $file_completely_parsed = $true ; }

  if (! $file_completely_parsed)
  {
    $file_in =~ s/.*[\\\/]//g ;
    abort ("String <\/mediawiki> not found at end of file '" . $file_in . "'. Incomplete or corrupt file? Pages read: $pages_read") ;
  }

  if (($pages_read == 0) || (($revisions_read == 0)))
  {
    $file_in =~ s/.*[\\\/]//g ;
    abort ("No data found in file '" . $file_in . "': $pages_read pages, $revisions_read revisions. File empty? XML layout changed?") ;
  }

  &LogT ("\n\nPages read: $pages_read. Revisions read: $revisions_read \n\n") ;

  &LogT ("Bytes written to events file: "  . &i2KbMb ($total_bytes_compressed_events) . 
	 " (uncompressed would have been " . &i2KbMb ($total_bytes_raw_events) . ")\n") ;

  if (! $prescan)
  { close EDITS_USER_MONTH_NAMESPACE_LOG ; }


  close REVERTS_SAMPLE ;
  close REVERTED_EDITS ;
}

sub XmlReadUntil
{
  my $text = shift ;
  my $lines_read = 0 ;

  while ($line = <FILE_IN>)
  {
    # $line =~ s/redirect/zblabla/ig ; # Oct 2016 temporarily remove all redirects for test

    # only when full archive dump is processed check each revision for being a redirect
    # in stub dump there can be a <redirect [some article title]> attribute, determined by #REDIRECT (or other language equivalent) (used to be for last revision?)
    # note that very last revision in dump could be beyond last date which should be processed, could cause small (negligible) discrepancies
    # when article changed from redirect to normal or vice versa very recently
    if ($edits_only && ($line =~ /<redirect /))
    { $edits_only_page_is_redirect = $true ; }


    $bytes_read += length ($line) ;
    if ($lines_read_xml_read_until++ % 1000 == 0)
    { &XmlReadProgress ; }

    if (($line =~ /<\/mediawiki>/) && ($text !~ /<\\\/mediawiki>/))
    {
      $file_in =~ s/.*[\\\/]//g ;
      abort ("String <\/mediawiki> found too soon, while searching for '$text'.") ;
    }

    if ($line =~ /$text/)
    { last ; }
  }
  chomp ($line) ;
}

sub XmlReadProgress
{
  while ($bytes_read > ($mb_read + 10) * $Mb)
  {
    ($min, $hour) = (localtime (time))[1,2] ;
    if ($prev_min ne $min)
    {
      &WriteTraceBuffer ;
      $trace_new_line = $true ;

      $prev_min = $min ;
      $mb_counts = 0 ;

      if (! $prescan)
      {
        $sec_run = (time - $timestart) ;
        $min_run = int ($sec_run / 60) ;
        if (($min % $deltaLogC == 0) || ($min_run - $min_run_LogC > 10))
        {
          $min_run_LogC = $min_run ;

          $mb_delta = $mb_read - $mb_read_prev ;
          $mb_read_prev = $mb_read ;
          if ($deltaLogC > 0)
          { $mb_per_hour = sprintf ("%.0f", (60 * $mb_delta) / $deltaLogC) ; }
          if ($time > $timestart_parse)
          { $pages_per_min = sprintf ("%.0f", $pages_read / ((time - $timestart_parse)/60)) ; }

          my $edits_prev = 0 ;
          my $edits_now  = 0 ;
          if ($edits_total_previous_run > 0)
          {
            $edits_now     = $edits_total_namespace_a + $edits_total_namespace_x ;
            $edits_compare = $edits_now / $edits_total_previous_run ;
          }

          &LogC ("\n" . sprintf ("%02d", $hour) . ":" . sprintf ("%02d", $min) . ":00 " . int($min_run/60) . "h" . sprintf ("%02d",$min_run%60) . " " .
                sprintf (" %4.1f\%", 100 * $edits_compare) .
                " " . sprintf ("%6d Mb", $mb_read) .
                "=+" . sprintf ("%5d Mb", $mb_delta) .
                sprintf ("~%5d Mb/hr", $mb_per_hour) .
                " free:$disk_free used:$disk_used" .
                " pages:$pages_read ($pages_per_min/min)\n") ;

          if ($trace_mem_once_an_hour ++ % 6 == 0) # 6 times 10 minutes
          { &TraceMem ; }
        }
      }
    }

    $mb_counts ++ ;
    if ($mb_counts > 10)
    {
      $mb_counts = 0 ;
      &Log (" \n           ") ;
    }
    &Log (($mb_read += 10) . " ") ;
    $trace_new_line = $false ;
  }
}

sub XmlReadBetween
{
  my $tag = shift ;
  &XmlReadUntil ("<$tag>") ;

  my $text = $line ;
  $text =~ s/^.*<$tag>// ;
  while (($line !~ /<\/$tag>/) && ($line = <FILE_IN>))
  {
    $bytes_read += length ($line) ;
    chomp ($line) ;
    $text .= $line ;
  }
  $text =~ s/^\s*// ;
  $text =~ s/<\/$tag>.*$// ;
  $text =~ s/>\s*</></g ;
  $text =~ s/\s*$// ;

  return ($text) ;
}

sub ReadInputXmlNamespaces
{
  my $log = "Parse namespace tags\n" ;
  &XmlReadUntil ('<siteinfo>') ;
  &XmlReadUntil ('<namespaces>') ;
  while ($line = <FILE_IN>)
  {
    $bytes_read += length ($line) ;
    if ($line =~ /<namespace /)
    {
      chomp $line ;
      $key  = $line ;
      $name = $line ;
      $key  =~ s/^.*key="([^\)]*)".*$/$1/ ;

      if ($line =~ /<namespace[^>]*\/>\s*$/)
      { $name = "" ; }
      else
      { $name =~ s/^.*<namespace[^\]]*>([^\]]*)<.*$/$1/ ; }
      $log .= sprintf ("%4s",$key) . " -> '$name'\n" ;
      $namespaces    {$name} = $key ;
      $namespacesinv {$key}  = $name ;
    }
    if ($line =~ /<\/namespaces>/) { last ; }
  }
  &XmlReadUntil ('</siteinfo>') ;

  &LogT ("\n$log\n") ;
}

# now that old sql code has been removed undo the following: (7/2006)
# unescape and escape so that text is in old sql escaped format
sub XmlToSql
{
#my $xmltosql0 = code_started() ;
  my $textref = shift;

#my $xmltosql1 = code_started() ;

# unescape xml
  if ($$textref =~ /\&/)
  {
#my $xmltosql11 = code_started() ;
    $$textref =~ s/&lt;/</sgo;
    $$textref =~ s/&gt;/>/sgo;
 #  $$textref =~ s/&apos;/\'/sgo; # obsolete ?
    $$textref =~ s/&quot;/\"/sgo;
    $$textref =~ s/&amp;/&/sgo;
#record_time ("XmlToSql11", $xmltosql11) ;
  }

#record_time ("XmlToSql1", $xmltosql1) ;
#my $xmltosql2 = code_started() ;

# escape sql
# if ($$textref =~ /[\\\r\0\x1A"']/) # some char's obsolete
  if ($$textref =~ /[\\"']/)
  {
#my $xmltosql21 = code_started() ;
    $$textref =~ s/\\/\\\\/sgo;
  # $$textref =~ s/\r/\\r/sgo; # obsolete ?
  # $$textref =~ s/\0/\\0/sgo; # obsolete ?
#record_time ("XmlToSql21", $xmltosql21) ;
#my $xmltosql22 = code_started() ;
  # $$textref =~ s/\x1A/\\Z/sgo; # obsolete ?
    $$textref =~ s/"/\\"/sgo;
# $text =~ s/'/\\'/sgo;
    $$textref =~ s/\\\'/\#\*\$\@/sgo ; # use encoded single quotes needed for old sql format
#record_time ("XmlToSql22", $xmltosql22) ;
  }

#my $xmltosql3 = code_started() ;
  $$textref =~ s/\n/\\n/sgo;
#record_time ("XmlToSql3", $xmltosql3) ;

# code_complete ("XmlToSql2", $xmltosql2) ;
# code_complete ("XmlToSql0", $xmltosql0) ;

#  return ($text) ;              # to differentiate between quotes in text and added by dump
}


sub ReadInputXmlPage
{
  use Fcntl 'O_RDWR', 'O_CREAT';

  my $time_start_page = time ;
  my $bytes_read_page = $bytes_read ;

  undef @revisions ;
  undef %edits_user_month_namespace ;
  undef %edits_user_month_namespace_28 ;
  $edits_only_page_is_redirect = $false ;

  if ($use_tie)
  {
    tie @revisions, 'Tie::File', $file_revisions, recsep => '*-*&^^&', mode => O_RDWR | O_CREAT, memory => $threshold_tie_file ;
    tied (@revisions)->defer ;
  }
  my $ndx_revisions = 0 ;

  my $namespace  = 0 ;
  my $article_type = '-' ;
  my $edits ;

  &XmlReadUntil ('<title>') ;

  $title = $line ;
  $title =~ s/^.*<title>(.*)<\/title>.*$/$1/ ;
  $title_full = $title ;

  if ($title =~ /Pearle\//) # script stalls on http://en.wikipedia.org/wiki/User:Pearle/categories-alpha
  { return ; }

  if ($title =~ /\:./)
  {
    $name = $title ;
    $name =~ s/\:.*$// ;
    $namespace = $namespaces {$name} + 0 ; # enforce numeric
    if (! defined $namespaces {$name})
    {
      $undef_namespaces {$name} ++ ;
      $namespace = 0 ;
    }

    if ($namespace != 0)
    { $title =~ s/^[^\:]*\:// ; }
  }

  XmlToSql \$title ;

  if (! $prescan)
  { $total_per_namespace {$namespace} ++ ; }

  # only when full archive dump is processed check each revision for being a redirect
  # in stub dump there can be a <redirect /> attribute, determined by #REDIRECT (or other language equivalent) in last revision
  $revision_is_redirect   = $false ; # will be relevant for stub dumps only

  &XmlReadUntil ('<id>.*<\/id>') ; # zzz
  $pageid = $line ;
  $pageid =~ s/^\s*<id>(.*)<\/id>.*$/$1/ ;

  if ($pageid <= $pageid_prev)
  { &LogT ("Page id $pageid out of order: follows page id $pageid_prev!\n") ; }
  $pageid_prev = $pageid ;

  if ($false) # (($language eq "en") && (($mb_read >= 474000) && ($mb_read <= 475000)))
  {
    unlink $file_trace_progress ;
    my ($min, $hour) = (localtime (time))[1,2] ;
    my $Now =  sprintf ("%02d", $hour) . ":" . sprintf ("%02d", $min) ;
    open "FILE_TRACE", ">", $file_trace_progress || abort ("Perl file '$file_trace_progress' could not be opened.") ;
    print FILE_TRACE "$Now Title [$title] Namespace [$namespace] Id [$pageid]\n" ;
    close FILE_TRACE ;
  }

  $first_revision = $true ;
  $totsize_revisions = 0 ;
  $tot_revisions_reguser = 0 ;
  $time_prev = '' ;

  &XmlReadUntil ('<revision>') ;
  $sha1_list = "" ;
  undef @edit_history ;
  $revision_cnt = 0 ;

  $data_page_created = '' ;

  while ($line =~ /<revision>/)
  {
    ($article, $time, $user, $userid, $usertype, $comment, $sha1) = &ReadInputXmlRevision ($namespace) ;

    my $date = substr ($time,0,8) ;
    last if $date > $dumpdate ;

    if ($first_revision)
    {
      my ($title2, $user2) ;
      ($title2   = $title)   =~ s/,/&comma;/g ;
      ($user2    = $user)    =~ s/,/&comma;/g ;

      $user_page_creator     = $user2 ;
      $usertype_page_creator = $usertype ;
      $userid_page_creator   = $userid ;
      $yyyymmddhhnn          = substr ($time,0,4).'-'.substr ($time,4,2).'-'.substr ($time,6,2).' '.substr ($time,8,2).':'.substr ($time,10,2) ;
      $data_page_created     = "$yyyymmddhhnn,$namespace,$usertype,$user2,$userid,$title2" ;
      $yymm_page_created     = substr ($time,2,4) ;

      if (($namespace == 6) && ($article =~ /uploadwizard/i))
      {
        if ($article !~ /\[\[[^\]]*uploadwizard[^\]]*\]\]/i)
        {
          &LogQ ("\n\narticle '$title' uploadwizard? $article\n\n") ;
          next ;
        }
        ($cat_uploadwizard = $article) =~ s/^.*?\[\[ ([^\]]*uploadwizard[^\]]*) \]\].*$/$1/ixos ; # case insensite , ignore newlines/spaces, compile once
        $cat_len = length ($cat_uploadwizard) ;
        if ($cat_len > 100)
        {
          $cat_uploadwizard = "uploadwizard (article '$title' cat tag too long: $cat_len bytes)" ;
          &Log ("\narticle '$title': cat_uploadwizard tag too long: $cat_len bytes)\n$article\n") ;
        }

        $data_page_created .= ",$cat_uploadwizard" ;
      }

      my ($year,$month,$day,$hour,$min,$sec) = $time =~ m/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ ;
      my $time_gm    = timegm ($sec, $min, $hour, $day, $month-1, $year-1900) ;
      my $days_passed = int (($dumpdate_gm - $time_gm) / (1440 * 60)) ;

      $page_created_recently = ($days_passed < 30) ;
    }

    if (! $prescan)
    { &DetectReverts ($namespace, $time, $user, $usertype, $comment, $sha1) ; }

    if ($reverts_only)
    { &XmlReadUntil ('(?:<revision>|<\/page>)') ; next ; }

    if ($dump2csv)
    { print FILE_DUMP_CSV &csv($namespace).&csv($time).&csv3($title_full).&csv3($user).&csv3($article)."\n" ; }

  # if (($language eq "en") && (($mb_read >= 474000) && ($mb_read <= 475000)))
  #  {
  #    my ($min, $hour) = (localtime (time))[1,2] ;
  #    my $Now =  sprintf ("%02d", $hour) . ":" . sprintf ("%02d", $min) ;
  #    open "FILE_TRACE", ">>", $file_trace_progress || abort ("Perl file '$file_trace_progress' could not be opened.") ;
  #    print FILE_TRACE "$Now [$time] User [$user]\n" ;
  #    close FILE_TRACE ;
  #  }

    my $yymm = substr ($time,0,6) ;
    $edits_per_namespace_per_month {"$yymm$namespace$usertype"} ++ ;
    if ($first_revision)
    {
      $first_revision = $false ;
      my $ext = $title ;

      if (! $prescan)
      {
        $new_titles_per_namespace_per_month {"$yymm$namespace"} ++ ;
        if ($namespace == 6)
        {
          if ($ext =~ /\.\w{1,4}$/)
          {
            $ext =~ s/^.*?\.([^\.]+$)/$1/ ;
            $ext = lc ($ext) ;
            $ext =~ s/jpeg/jpg/ ;
            $binaries_per_month {"$yymm$ext"} ++ ;
          }
        }
      }
    }

    # only analyze article content for last edit per day
    # saves one third of total job run length
    if ($time_prev ne '')
    {
      if ((substr ($time,0,$period_significant_digits) eq substr ($time_prev,0,$period_significant_digits)) && ($article !~ /\/timeline/i))
      { $revisions [$ndx_revisions++] = $revision_prev_same_period  ; $articles_eq++ ;}
      else
      { $revisions [$ndx_revisions++] = $revision_prev_not_same_period  ; $articles_ne++ ;}


      if ($use_tie)
      {
        if (($ndx_revisions > 0) && ($ndx_revisions % 1000 == 0))
        {
          tied (@revisions)->flush ;
          $size_rev = -s $file_revisions ;
          if ($size_rev > 0)
          {
            $tracemsg .= "Revisions buffered: $ndx_revisions -> File size RevisionsCached: " . int ($size_rev/1024) . " Kb\n" ;
            &WriteTraceBuffer ;
          }
        }
      }
    }

    $time_prev     = $time ;
    # store with $article = #@ if costly counts should be skipped on this revision
    $revision_prev_not_same_period = "$pageid`$article`$time`$user`$userid`$usertype`" ;
    $revision_prev_same_period     = "$pageid`#@`$time`$user`$userid`$usertype`" ;

    &XmlReadUntil ('(?:<revision>|<\/page>)') ;
  }

  return if $reverts_only ;

  if ($time_prev ne '')
  { $revisions [$ndx_revisions++] = $revision_prev_not_same_period  ; $articles_ne++ ;}


  $tot_revisions = $#revisions+1 ;
  $contributing_reg_users = keys %contributing_reg_users ;
  $contributing_ip_users  = keys %contributing_ip_users ;

  # For list of most edited articles:
  # only log records with revisions >= 25
  # only log records with revisions > x such that at least top 5000 records with 25+ are all logged
  # therefore periodically determine the cut off point
  # later the file will be sorted and all records below rank 5000 discarded
  if (! $prescan)
  {
    # for each 1000th article adjust cut off point
    if ($adapt_tot_revisions_min++ % 1000 == 0)
    {
      $tot_revisions_cumulative = 0 ;
      foreach $revisions_cnt (sort { $b <=> $a } keys %tot_revisions_cnt)
      {
        $tot_revisions_cumulative += $tot_revisions_cnt {$revisions_cnt} ;
        # 5000+ records written with edit count $tot or higher
        if ($tot_revisions_cumulative > 5000)
        {
          # raise cut off point ?
          if ($tot_revisions_min < $revisions_cnt)
          {
            $tot_revisions_min = $revisions_cnt ;
            $records_all_edits_per_article    += 0 ; # force numeric presentation
            $records_logged_edits_per_article += 0 ; # force numeric presentation
            if ($records_all_edits_per_article > 0)
            { $records_logged_percentage = sprintf ("%.0f", (100 * $records_logged_edits_per_article)/$records_all_edits_per_article) + 0 ; } # force numeric presentation

            if ($trace_log_edit_count_raised++ % 10 == 0)
            {
              &LogT ("\n\nLog edit count for articles with revision count >= $tot_revisions_min " .
                     "($records_logged_edits_per_article/$records_all_edits_per_article [$records_logged_percentage\%] edit counts logged)\n\n        ") ;
            }
          }
          last ;
        }
      }
    }
    if ($tot_revisions_min < 25)
    { $tot_revisions_min = 25 ; }

    $records_all_edits_per_article ++ ;
    if ($tot_revisions >= $tot_revisions_min)
    {
      $tot_revisions_cnt {$tot_revisions} ++ ;
      $records_logged_edits_per_article ++ ;
      $revisions_cnt {$tot_revisions} ++ ;
      print FILE_EDITS_ARTICLES "$language,$tot_revisions,$tot_revisions_reguser,$totsize_revisions,$contributing_reg_users,$contributing_ip_users,$title_full\n" ;
    }
  }

  $current_revision = $true ;

  if (($article ne "") && (! $prescan))
  {
    if (($namespace % 2 == 0) &&
        ($namespace != 0) && ($namespace != 10) && ($namespace != 14))
    { &CollectCategories ($namespace) ; }
  }

  if ($use_tie)
  {
    tied (@revisions)->flush ;
    $size_rev = -s $file_revisions ;
  }

  # process revsions backwards in time, from latest to earliest, this way only latest revison for any given day is analyzed
  $most_recent_revision = $true ; # first revision to get from stack (last revision added to table) is most recent, remember article type to classify creator
  while ($ndx_revisions > 0)
  {
    $text = $revisions [--$ndx_revisions] ;

    my ($pageid, $article, $time, $user, $userid, $usertype) = split ('\`', $text) ;
    if ($pageid !~ /^\d+$/)
    {
      &Log ("Title '$title' : page id not numeric (prev page id $pageid_prev): '" . substr ($pageid,0,80) . "...'\n") ;
      if ($pageid_not_numeric++ > 1000)
      { abort ("Too many pages with non numeric page id") ; }
      last ;
    }

    $article   =~ s/\*\{\|\}\*/\`/g ;
    $user      =~ s/\*\{\|\}\*/\`/g ;
    $time      =~ s/\*\{\|\}\*/\`/g ;

    XmlToSql \$article ;
    XmlToSql \$user ;

    # ignore runaway bot
    if (($mode eq "wk") && ($language eq "bg") && ($user eq "Bgbot")) { next ; }

my $start_process_revision = code_started() if $record_time_process_revision_main ;

    $article_type = &ProcessRevision ($current_revision, $ndx_revisions, $pageid, $namespace, $title, $article, $user, $userid, $time, $usertype) ;

    if ($most_recent_revision)
    {
      $most_recent_revision = $false ;
      $most_recent_article_type_for_this_page = $article_type ;
    }

code_complete ("ProcessRevision", $start_process_revision) if $record_time_process_revision_main ;

    if ($prescan)
    { return ; }

    $current_revision = $false ;
  }

  return if $article_type =~ /^\!/ or $data_page_created eq '' ; # ignore record, e.g. incomplete current month

  # only when processing full archive dump article article type can be redirect (R) or without internal link (-)
  if ($mode eq "wk") 
  { $content_page = ($most_recent_article_type_for_this_page !~ /R/) ; } # for wiktionary no longer test for internal link
  else
  { $content_page = ($most_recent_article_type_for_this_page !~ /-|R/) ; } 
  
# if (! $edits_only_page_is_redirect && $content_page)
  if ($content_page) # Dec 2016 redirects are no longer exluded from edit(or) ocunts, they are still for article counts
  {
    if (&NameSpaceArticle ($language, $namespace))
    { &IncUserData ($user_page_creator, $useritem_create_reg_namespace_a) ; }
    else
    { &IncUserData ($user_page_creator, $useritem_create_reg_namespace_x) ; }

    if ($page_created_recently)
    {
      if (&NameSpaceArticle ($language, $namespace))
      { &IncUserData ($user_page_creator, $useritem_create_reg_recent_namespace_a) ; }
      else
      { &IncUserData ($user_page_creator, $useritem_create_reg_recent_namespace_x) ; }
    }

    # note that totals for these metrics per month can be slightly different from total article counts (column G in StatisticsMonthly.csv
    # here the creation date for the article is leading, and articles are counted when they pass the test for 'valid article' on last revision
    # in column G articles are only counted when they pass the test for 'valid article', which could be several revisions later
    if (&NameSpaceArticle ($language, $namespace))
    {
      if ($usertype_page_creator eq 'R')
      { $created_per_month_reg  {$yymm_page_created} ++ ; }
      elsif ($usertype_page_creator eq 'A')
      { $created_per_month_anon {$yymm_page_created} ++ ; }
      elsif ($usertype_page_creator eq 'B')
      { $created_per_month_bot  {$yymm_page_created} ++ ; }
    }
  }

  print FILE_CREATES "$most_recent_article_type_for_this_page,$data_page_created\n" ;

  if (&NameSpaceArticle ($language, $namespace) && (! $prescan)) # strategy
  {
    my $month      = "" ;
    my @unique_reg_users_per_month = keys %contributing_reg_users_per_month ;
    foreach my $month_user (@unique_reg_users_per_month)
    {
      $month = substr ($month_user,0,6) ;
      $user  = substr ($month_user,7) ;
      $users_per_month {$month} ++ ;
      $months_edited_per_article {$month} ++ ;
    }
    foreach my $month (sort keys %months_edited_per_article)
    {
      $users_this_month = $users_per_month {$month} ;
      for ($i = 0 ; $i <= 24 ; $i++)
      {
        $month_i = $month . sprintf ("%02d",$i) ;
        if ($users_this_month >= $zeitgeist_reg_users_rank {$month_i})
        {
          for ($j = 24 ; $j >= $i ; $j--)
          {
            $month_j   = $month . sprintf ("%02d",$j) ;
            $month_j_1 = $month . sprintf ("%02d",$j-1) ;
            if ($zeitgeist_reg_users_rank  {$month_j} ne "")
            {
              $zeitgeist_reg_users_rank  {$month_j} = $zeitgeist_reg_users_rank  {$month_j_1} ;
              $zeitgeist_reg_users_title {$month_j} = $zeitgeist_reg_users_title {$month_j_1} ;
            }
          }
          $zeitgeist_reg_users_rank  {$month_i} = $users_this_month ;
          $zeitgeist_reg_users_title {$month_i} = $title ;
          last ;
        }
      }
    }
    undef %users_per_month ;
    undef %months_edited_per_article ;

# to be refined:
# count all edits but no more than one per user/ip_address per 30 min

#    @unique_all_users_per_month = keys %contributing_all_users_per_month ;
#    foreach my $month_user (@unique_all_users_per_month)
#    {
#      $month = substr ($month_user,0,6) ;
#      $user  = substr ($month_user,7) ;
#      @users_per_month {$month} ++ ;
#      @months_edited_per_article {$month} ++ ;
#    }
#    foreach $month (sort keys %months_edited_per_article)
#    {
#      $users = @users_per_month {$month} ;
#      for ($i = 0 ; $i <= 9 ; $i++)
#      {
#        if ($users >= @ZeitGeistAllUsersRank {"$month$i"})
#        {
#          for ($j = 9 ; $j >= $i ; $j--)
#          {
#            if (@ZeitGeistAllUsersRank  {"$month$j"} ne "")
#            {
#              @ZeitGeistAllUsersRank  {"$month$j"} = @ZeitGeistAllUsersRank  {"$month" . ($j-1)} ;
#              @ZeitGeistAllUsersTitle {"$month$j"} = @ZeitGeistAllUsersTitle {"$month" . ($j-1)} ;
#            }
#          }
#          @ZeitGeistAllUsersRank  {"$month$i"} = $users ;
#          @ZeitGeistAllUsersTitle {"$month$i"} = $title ;
#          last ;
#        }
#      }
#    }
#    undef %users_per_month ;
#    undef %months_edited_per_article ;
  }
  undef %contributing_reg_users ;
  undef %contributing_ip_users ;
  undef %contributing_reg_users_per_month ;
  undef %contributing_all_users_per_month ;

  # log edits per user per namespace for this article, to be aggregated later 
  if (! $prescan)
  {
    # also log edit count for first 28 days of months (could be zero), so that normalized monthly activity (regardless of length of month) becomes feasible
    foreach my $key (sort keys  %edits_user_month_namespace)
    { print EDITS_USER_MONTH_NAMESPACE_LOG "$key," . $edits_user_month_namespace {$key} . "," . ($edits_user_month_namespace_28 {$key}+0)  . "\n" ; }
  }

  if ($use_tie)
  {
    if ($size_rev > 0)
    { $size_rev_0_gt ++ ; }
    else
    { $size_rev_0_eq ++ ; }

    if ($size_rev > $size_rev_max)
    {
      $size_rev_max = $size_rev ;
      $tracemsg .= "Max size $file_revisions -> " . &i2KbMb ($size_rev_max) . "\n" ;
    }

    if ((($size_rev_0_gt + $size_rev_0_eq) % 10000) == 0)
    {
      $tracemsg .= "Revisions cached on " . ($size_rev_0_gt+0) . " / " . (($size_rev_0_gt + $size_rev_0_eq)/1000) . "K articles or " .
                   sprintf ("%.3f", 100* ($size_rev_0_gt/($size_rev_0_gt + $size_rev_0_eq))) . "\%.\n" ;
    }

    tied (@revisions)->discard ;
  }

  undef @revisions ;

  if (time - $time_start_page > 60)
  {
    $tracemsg .= "Large page took " . ddhhmmss(time - $time_start_page) . ", " .
                 "$tot_revisions rev. by $contributing_reg_users reg./$contributing_ip_users unreg., " .
                 sprintf ("%.0f", ($bytes_read - $bytes_read_page) / $Mb) . "/" .
                 sprintf ("%.0f", $size_rev / $Mb) . ": $title\n" ;
  }

  if (++ $revision_count_report_reverts % 1000000 == 0)
  {
    &Log ("\n\n$reverts_sha1_articles_bots bot 'reverts' out of $reverts_sha1_articles SHA1 reverts = " .
          "-B: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_1 / $reverts_sha1_articles) .
          ", B-: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_2 / $reverts_sha1_articles) .
          ", BB: " . sprintf ("%.1f%", 100 * $reverts_sha1_articles_bots_3 / $reverts_sha1_articles) .
          "\n\n") ;

    &LogT ("\nRevert flags:\n") ;
    foreach $key (sort keys %reverts_all)
    { &LogT ("$key: ${reverts_all{$key}}\n") ; }
  }
}

sub ReadInputXmlRevision
{
  my $namespace = shift ;

  $revisions_read ++ ;

  if ($filesizelarge && ($revisions_read % 100000 == 0))
  {
    $pages_read2     = sprintf ("%.0f", $pages_read / 1000) ;
    $revisions_read2 = sprintf ("%.0f", $revisions_read / 1000) ;
    $revs_per_hour   = '-' ;
    $hours_total_for_run = '-' ;
    $hours_to_go_for_run = '-' ;
    if (time - $timestart_parse > 0)
    { $revs_per_hour   = sprintf ("%.0f", $revisions_read / ((time - $timestart_parse) / 3600)) ; }
    if ($revs_per_hour > 0)
    {
      $hours_total_for_run = sprintf ("%.0f", $edits_total_prev_run / $revs_per_hour) ;
      $hours_to_go_for_run = sprintf ("%.0f", $hours_total_for_run - (time - $timestart_parse) / 3600) ;
    }
    &LogT ("\n\nParsing since " . ddhhmmss (time - $timestart_parse). ". Pages read: ${pages_read2}k. Revisions read: ${revisions_read2}k. Per hour $revs_per_hour/hr. Parse duration ~ $hours_total_for_run hrs, $hours_to_go_for_run hrs to go\n") ;
  }

  my ($time, $article, $contributor, $user, $userid, $sha1, $comment) ;

  &XmlReadUntil ('<timestamp>') ;
  $timestamp = $line ;
  $time = $timestamp ;
  $time =~ s/^.*<timestamp>(.*)<\/timestamp>.*$/$1/ ;
  $time =~ s/^(\d\d\d\d).(\d\d).(\d\d).(\d\d).(\d\d).(\d\d).*$/$1$2$3$4$5$6/ ;

  $contributor = &XmlReadBetween ('contributor') ;

  $user = '?' ;
  $userid = '?' ;

  if ($contributor =~ /<username>(.*)<\/username>/)
  { $user = $1 ; }
  if ($contributor =~ /<id>(.*)<\/id>/)
  { $userid = $1 ; }
  if ($contributor =~ /<ip>(.*)<\/ip>/)
  { $user = $1 ; }
  # print "\n\nContributor\nId $userid User '$user'\n" ;

  if (($user eq '?') && ($userid eq '?'))
  { &LogQ ("\n\nTimestamp $timestamp:\nTitle '$title':\nNo user info retrieved from contributor element:\n'$contributor'\n\n") ; }

  &XmlReadUntil ('(?:<text |<comment)') ;

  if (($line =~ /<comment>(.*)<\/comment>/) || ($line =~ /<comment([^>]+)\/>/))
  {
    $comment = $1 ;
    &XmlReadUntil ('<text ') ;
  }
  elsif ($line =~ /<comment(.*)$/) # <comment> will fail: missed &XmlReadUntil ('<text ') ; on e.g. <comment deleted='foo'\/>
  {                                # in stub dump this gave memory as it never satisfied "while (($line !~ /<\/text>/) && ($line = <FILE_IN>))"
    $comment = $1 ; # Q&D: incomplete comment
    &XmlReadUntil ('<text ') ;
  }
  chomp ($line) ;

  if ($line =~ /<text[^\>]*\/>/)
  { $article = "" ; }
  else
  {
    $article = $line ;
    $article =~ s/^.*<text[^\>]*>// ;
    my $loop_cycles = 0 ;
    while (($line !~ /<\/text>/) && ($line = <FILE_IN>))
    {
      $bytes_read += length ($line) ;
      # chomp ($line) ;
      $article .= $line ;
      if ((++$loop_cycles % 1000 == 0) && (length ($article) > 10000000)) # is 'length ($article)' costly at huge strings ?
      {
        &LogQ ('*' x 80 . "\nArticle $title, time $time, user $user, userid $userid, userseqno $userseqno, pageid $pageid\n$article") ;
        $article = '' ; # contain memory leak
      }
    }

    $article =~ s/<\/text.*$// ;
    $totsize_revisions += length ($article) ;
  }

  &XmlReadUntil ('<sha1') ;
  if ($line !~ /<\/sha1>/)
  { $sha1 = 0 ; }
  else
  { ($sha1 = $line) =~ s/^.*?<sha1>([^<]*)<.*$/$1/g ; }
        
  my $month = substr ($time,0,6) ;
  my $date  = substr ($time,0,8) ;

  if (($comment =~ /^bot/i) || ($comment =~ /^robot/i)) # only when comment starts with (ro)bot take this as clue for bot
  { $usertype = 'B' ; } # bot
  elsif (&IpAddress ($user))
  { $usertype = 'A' ; } # anonymous
  else
  {
    if ($bots {$user} == 0)
    { $usertype = 'R' ; } # registered ;
    else
    { $usertype = 'B' ; } # bot
  }

  if (($date <= $dumpdate) && (! $prescan))
  {
    if ($usertype eq "A")
    { $contributing_ip_users {$user}++ ; }
    else
    {
      $tot_revisions_reguser++ ;
      $contributing_reg_users {$user}++ ;
      if ($usertype eq "R")
      { $contributing_reg_users_per_month {"$month-$user"}++ ; }
    }
  }

  # not interested in content, only in when and by whom it was edited
  if ((! &NameSpaceArticle ($language, $namespace)) && ($namespace != 10) && ($namespace != 14))   # strategy
  { $article = "" ; }

  # not interested in content, only in when and by whom it was edited
  if ($edits_only) # EZ 2012-09-05 was 'if (! $edits_only)' ????
  {
    if ($article =~ /#REDIRECT/i)
    { $article = "#REDIRECT[[X]]" }
    elsif ($article =~ m/\[\[/)
    { $article = "[[X]]" }
    else
    { $article = "" ; }
  }

  $article =~ s/`/*{|}*/g ;
  $user    =~ s/`/*{|}*/g ;
  $time    =~ s/`/*{|}*/g ;

# my $start_process_sha1a = code_started() if $record_time_process_sha1 ;
# $sha1 = sha1_hex($article) ; # 2013 June: now collect sha1 checksum from xml
# code_complete ("GenerateSha1PerArticle", $start_process_sha1a) if $record_time_process_sha1 ;

  if ($sha1 eq '')
  { &Log ("$article $time: sha1 not found\n") ; }

  return ($article, $time, $user, $userid, $usertype, $comment, $sha1) ;
}

sub DetectReverts
{
  my ($namespace, $time, $user, $usertype, $comment, $sha1) = @_ ;

  return if $sha1 eq '' ; # no checksum: dump contains <sha1 /> # 2014-06-17 test used to be == 0 which makes many valid sha1's go rejected  

  my ($prev_revert,$prev_namespace,$prev_title,$prev_time,$prev_edits_ago,$prev_usertype,$prev_user,$prev_comment) ;

my $start_process_sha1b = code_started() if $record_time_process_sha1 ;

  if (&NameSpaceArticle ($language, $namespace))
  { $revert = 'N' ; }
  else
  { $revert = '-' ; }

  if ($language eq 'de')
  {
    if ($comment =~ /(?:\brvv?\b|\brev\b|\brevert|undo|undid|spam|vandal|r..?ckg..?ngig|wiederher|entfernt)/i)
    { $revert .= 'C' ; } # revert
    else
    { $revert .= '-' ; }
  }
  elsif ($comment =~ /(?:\brvv?\b|\brev\b|\brevert|teruggerol|herstel|undo|spam|vandal|vandaal|terug|ongedaan)/i)
  { $revert .= 'C' ; } # revert
  else
  { $revert .= '-' ; }

  # get highest index of $sha1 if any, else -1
  $index_sha1 = index ($sha1_list, $sha1) ;
  $index_sha1_last = $index_sha1 ;
  while ($index_sha1 > -1)
  {
    $index_sha1 = index ($sha1_list, $sha1, $index_sha1+1) ;
    if ($index_sha1 > -1)
    { $index_sha1_last = $index_sha1 ; }
  }
  $index_sha1 = $index_sha1_last ;

  $index_sha1_delta = 0 ;
  if ($index_sha1 > -1)
  {
    $index_sha1_delta = sprintf ("%.0f", (length ($sha1_list) - $index_sha1) / 33) ; # each entry 32 chars + comma
    if ($index_sha1_delta > 1)
    { $revert .= 'M' ; } # revert based on comparing checksums
    else
    { $revert .= 'X' ; } # revert based on comparing checksums
  }
  else
  { $revert .= '-' ; }

  $sha1_list .= "$sha1," ;
  if ($revision_cnt++ >= 100)
  { $sha1_list = substr ($sha1_list,33) ; }

  if (($comment =~ /\brobot\b/i) || ($user =~ /conversion script/i) || ($user =~ /MediaWiki default/i))
  { $revert .= 'B' ; } # bot
  else
  { $revert .= '-' ; }

  if  ($bots {$user})
  { $revert .= 'B' ; } # bot
  else
  { $revert .= '-' ; }

  $revert .= $usertype ;

  my ($title2,$comment2,$user2) ;
  ($title2   = $title)   =~ s/,/\%2C/g ;
  ($comment2 = $comment) =~ s/,/\%2C/g ;
  ($user2    = $user)    =~ s/,/\%2C/g ;

  push @edit_history, "$revert ,$namespace,..,$title2,$time,$usertype,$user2,'$comment2'\n" ;

  $revert_after_secs = 0 ;
  if (($revert =~ /^..M/) && ($index_sha1_delta > -1)) # -1 => no changes in last submit (?)
  {
    ($prev_revert,$prev_namespace,$prev_edits_ago,$prev_title,$prev_time,$prev_usertype,$prev_user,$prev_comment)  = split (',', $edit_history [-$index_sha1_delta]) ;
    $revert .= $prev_usertype ;

    $revert_after_secs = yyyymmddhhmmssDiff ($time, $prev_time) ;
    $revert_after_ddhhmmss = ddhhmmss ($revert_after_secs) ;
    $revert_after_secs_fmt = sprintf ("%010d",$revert_after_secs) ;

    $reverts_after_month {substr ($prev_time,0,6)} += $revert_after_secs ;
    $reverts_after_year  {substr ($prev_time,0,4)} += $revert_after_secs ;
    $reverts_after_all                             += $revert_after_secs ;

    $reverts_after_month_sha1 {substr ($prev_time,0,6)}++ ;
    $reverts_after_year_sha1  {substr ($prev_time,0,4)}++ ;
    $reverts_after_all_sha1 ++ ;

    if (-$index_sha1_delta == -1)
    {
      &Log ("\n\n\nNon revert (previous revision is same) $revert,$namespace,$title,$time,$usertype,$user,'$comment'\n\n\n") ;
    }
    elsif (-$index_sha1_delta == -2)
    {
      if ($user eq $prev_user)
      {
        $revert .= 'S' ;
      }
      else
      { $revert .= '-' ; }
    }
    else
    {
      # check all revisions that will be reverted, all by reverting editor ?
      $self_revert = 'S' ; # self revert

      for ($i = -$index_sha1_delta ; $i <= -2 ; $i++) # -2 is last revision before revert action (-1 is revert action, is top of list)
      {
        my ($prev_revert,$prev_namespace,$prev_edits_ago,$prev_title,$prev_time,$prev_usertype,$prev_user,$prev_comment)  = split (',', $edit_history [$i]) ;
        if ($user ne $prev_user)
        { $self_revert = '-' ; last ; }
      }
      $revert .= $self_revert ;
    }
  }
  else
  { $revert .= '--' ; }

  if (($revert =~ /^.C/) || ($revert =~ /^..M/))
  {
    if ($revert =~ /^N.M/)
    { $reverts_sha1_articles++ ; }

    if ($revert =~ /^N.M(?:-B|B-|BB)/)
    {
      $reverts_sha1_articles_bots++ ;

      if ($revert =~ /^N.M-B/)
      { $reverts_sha1_articles_bots_1++ ; }
      elsif ($revert =~ /^N.MB-/)
      { $reverts_sha1_articles_bots_2++ ; }
      else
      { $reverts_sha1_articles_bots_3++ ; }

      if ($reverts_sha1_articles_bots % 250 == 0)
      {
        &Log ("\n$reverts_sha1_articles_bots bot 'reverts' out of $reverts_sha1_articles SHA1 reverts = " .
              "-B: " . sprintf ("%.2f%", 100 * $reverts_sha1_articles_bots_1 / $reverts_sha1_articles) .
              ", B-: " . sprintf ("%.2f%", 100 * $reverts_sha1_articles_bots_2 / $reverts_sha1_articles) .
              ", BB: " . sprintf ("%.2f%", 100 * $reverts_sha1_articles_bots_3 / $reverts_sha1_articles) .
              "\n") ;
      }
    }

    if (($revert =~ /^.C/) || ($revert =~ /^..M/))
    {
      $prev_revert =~ s/ //g ;

      $revert_edits_printed++ ;
      if ($revert_edits_printed % 1000 == 0) # flush
      {
        close REVERTED_EDITS ;
        open  REVERTED_EDITS, ">>", $file_csv_reverted_edits ;
      }

      if ($revert =~ /^.C-/) # comment contains revert etxt ?
      { print REVERTED_EDITS substr($time,0,6) . ",$revert,$namespace,$user2,$usertype,$title2,'$comment2'\n" ; }
      else
      { print REVERTED_EDITS substr($time,0,6) . ",$revert,$namespace,$user2,$usertype,$title2,'$comment2',-$index_sha1_delta,$revert_after_secs_fmt,$prev_time,$prev_revert,$prev_usertype,$prev_user\n" ; }
    }

    if ($reverts_all {$revert} < 50)
    {
      # revert detected based on (also) SHA1 info?
      if ($revert =~ /^..M/)
      {
        &WriteRevertsSample ("$revert,$namespace,-$index_sha1_delta,$title2,$time,$usertype,$user2,'$comment2'\n") ;

        # if just one edit is reverted present details of that edit
        if (-$index_sha1_delta == -2)
        {
          &WriteRevertsSample ($edit_history [-2]) ;
          &WriteRevertsSample ("Revert after $revert_after_ddhhmmss\n") ;
        }

        # present details of that edit that is restored
        &WriteRevertsSample ($edit_history [-$index_sha1_delta-1] . "\n") ;
      }
      else
      { &WriteRevertsSample ("$revert,$namespace,$title2,$time,-$index_sha1_delta,$usertype,$user2,$comment2\n") ; }
    }
  }

  $reverts_month {substr ($time,0,6).$revert}++ ;
  $reverts_year  {substr ($time,0,4).$revert}++ ;
  $reverts_all   {$revert}++ ;

code_complete ("GenerateSha1Results", $start_process_sha1b) if $record_time_process_sha1 ;
}

sub WriteRevertsSample
{
  my $line = shift ;

  print REVERTS_SAMPLE $line ;

  return ; # do not show onscreen

  if (! $trace_new_line)
  { print "\n" ; $trace_new_line = $false }

  print $line ;
}

sub ProcessRevision
{
  my ($current_revision, $ndx_revisions, $pageid, $namespace, $title, $article, $user, $userid, $time, $usertype) = @_ ;

  $booktitle = "" ;

  if ((($mode eq "wb") || ($mode eq "wv")) && &NameSpaceArticle ($language, $namespace) &&
      ($article ne "#@") && ($article !~ /(?:$redirtag)/i) &&
      ($article !~ /\{\{bereits nach de\.wikibooks\.org verschoben\}\}/))
  {
    $booktitle = &ProcessBookTitle ($title, $article, $current_revision) ;
  }

  if ($prescan)
  { return ('!1') ; }

  if ($time == 0) { return ('!2') ; } # found invalid revision in ja:

  ($year,$month,$day,$hour,$min,$sec) = $time =~ m/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ ;

  if (($month < 1) || ($month > 12))
  {
    &Log ("\nInvalid month '$month' on article '$title', ns $namespace, page id $pageid, user $user, time $time -> skip revision\n") ;
    return ('!3')  ;
  }

  $time_gm = timegm ($sec, $min, $hour, $day, $month-1, $year-1900) ;

  if ($time_gm > $dumpdate_gm_hi)
  {
    print "Ignore $year, $month, $user\n" ;
    return ('!4') ;
  }

my $start_process_revision1 = code_started() if $record_time_process_revision_main ;

code_complete ("ProcessRevision1", $start_process_revision1) if $record_time_process_revision_main ;

my $start_process_revision2 = code_started() if $record_time_process_revision_main ;

  # restore quotes
  $user   =~ s^\#\*\$\@^'^g ;

  if ($edits_only || (($mode eq "wp") && ($language eq "en")))
  {
    if (&IpAddress ($user))
    { $user = "an.on.ym.ous" ; }
  }

  $userseqno = &GetUserData ($user, $useritem_id) ; # may invoke PutUserData first to create new user record

  $revision_is_redirect = $false ;
  $article_type = '-' ;
  if (&NameSpaceArticle ($language, $namespace)) # strategy
  {
    ($revision_is_redirect, $article_type) = &CollectArticleCounts ($current_revision, $namespace, $pageid, $article, $user, $userseqno) ;


    $yymm  = sprintf ("%02d%02d", $year - 2000, $month, ) ;
    $edits_per_month {$yymm} ++ ;

    if ($usertype eq 'R')
    { $edits_per_month_reg  {$yymm} ++ ; }
    elsif ($usertype eq 'A')
    { $edits_per_month_anon {$yymm} ++ ; }
    elsif ($usertype eq 'B')
    { $edits_per_month_bot  {$yymm} ++ ; }

    if (not defined ($first_edit))
    { $first_edit = $time_gm ; }
    elsif ($time_gm < $first_edit)
    { $first_edit = $time_gm ; }
  }

code_complete ("ProcessRevision2", $start_process_revision2) if $record_time_process_revision_main ;

  my $start_process_revision3 = code_started() if $record_time_process_revision_main ;

  if ($article ne "#@") # #@ = more revisions for day same will follow -> skip costly counts
  {
    if (($mode eq "wp") && ($article =~ /<\/timeline>/i) && # strategy
        (&NameSpaceArticle ($language, $namespace) || ($namespace == 10)))
    {
      &WriteTimelines ($current_revision, $time, $namespace, $title, $user, $article); }

#    {
#      if ($current_revision)
#      { &CollectTimelines ($namespace, $title, $article, $user, $time_gm); }
#      else
#      {
#        my ($ns_title, $sha1) = &ChecksumTimelines ($namespace, $title, $article);
#        if ($sha1 ne "")
#        { &UpdateTimelineCounts ($ns_title, $sha1, $user, $time_gm); }
#      }
#    }

    if ($current_revision && (&NameSpaceArticle ($language, $namespace) || ($namespace == 14)))  # strategy
    { &CollectCategories ($namespace) }
  }

code_complete ("ProcessRevision3", $start_process_revision3) if $record_time_process_revision_main ;
my $start_process_revision4 = code_started() if $record_time_process_revision_main ;

  if (! $prescan)
  { &CollectUserCounts ($namespace, $user, $userid, $title, $revision_is_redirect, $time_gm, $usertype) ; }

code_complete ("ProcessRevision4", $start_process_revision4) if $record_time_process_revision_main ;

  return ($article_type) ;
}

sub CollectUserCounts
{
  my ($namespace, $user, $userid, $title, $revision_is_redirect, $time, $usertype) = @_ ;
  my ($namespace2, $user2) ;

  my ($day,$month, $year) = (localtime ($time))[3,4,5] ;
  $month++ ;
  $year += 1900 ;
  my $yymm   = sprintf ("%02d%02d", $year - 2000, $month) ;
  my $yyyymm = sprintf ("%04d-%02d", $year, $month) ;

  ($user2 = $user) =~ s/,/&comma;/g ;
  ($title2 = $title) =~ s/,/&comma;/g ;
  $namespace2 = sprintf ("%03d", $namespace) ;

# if ((! $revision_is_redirect) && ($usertype eq 'R')) # Oct 2016 do not count redirects or bots, like in other metrics
  if ($usertype eq 'R') # Dec 2016 redirects are no longer excluded from edit(or) ocunts, they are still for article counts
  {
    $edits_user_month_namespace {"$user2,$userid,$yyyymm,$namespace2"}++ ;
    if ($day <= 28)
    { $edits_user_month_namespace_28 {"$user2,$userid,$yyyymm,$namespace2"}++ ; }
  }

  if (&NameSpaceArticle ($language, $namespace)) # strategy
  { $edits_total_namespace_a ++ ; }
  else
  { $edits_total_namespace_x ++ ; }

  if (&IpAddress ($user))
  {
    if (&NameSpaceArticle ($language, $namespace)) # strategy
    {
      &IncUserData ($user, $useritem_edit_ip_namespace_a) ;
      $edits_total_ip_namespace_a ++ ;
    }
    else
    {
      &IncUserData ($user, $useritem_edit_ip_namespace_x) ;
      $edits_total_ip_namespace_x ++ ;
    }

    return ;
  }

  # count edits/creates per user

  if (&NameSpaceArticle ($language, $namespace)) # strategy
  { &IncUserData ($user, $useritem_edit_reg_namespace_a) ; }
  else
  { &IncUserData ($user, $useritem_edit_reg_namespace_x) ; }

  my $days_passed = int (($dumpdate_gm - $time) / (1440 * 60)) ;

  if ($days_passed < 30)
  {
    if (&NameSpaceArticle ($language, $namespace)) # strategy
    { &IncUserData ($user, $useritem_edit_reg_recent_namespace_a) ; }
    else
    { &IncUserData ($user, $useritem_edit_reg_recent_namespace_x) ; }
  }

# if ($namespace != 0) # strategy
# { return ; }

  my $nscat = "A" ; # article
  if (! &NameSpaceArticle ($language, $namespace)) # strategy
  {
    if ($namespace % 2 == 1)
    { $nscat = "T" ; } # talk
    else
    { $nscat = "O" ; } # other
  }

  # remember edits per user per month
  ($user2 = $user) =~ s/,/&#44;/g ;
# if (! $revision_is_redirect) # Dec 2016 redirects are no longer exluded from edit(or) ocunts, they are still for article counts
# {
    if ($filesizelarge) # zzz
    {
      my $yyyymm = sprintf ("%04d-%02d", $year, $month) ;
      my $file_events_user_month = $path_temp . "UserEditsPerMonth~$yyyymm" ;
      my $file = $files_events_user_month {$file_events_user_month} ;
      if ($file eq "")
      {
        $file = "UserEditsMonth~$yymm" ;
        $files_events_user_month {$file_events_user_month} = $file ;
        open $file, ">", $file_events_user_month ;
        binmode ($file) ;
      }
      print {$file} "$user2,$usertype,$nscat\n" ;
    }
    else
    { @edits_per_user_per_month {"$yymm,$user2,$usertype,$nscat"} ++ ; }

#   if ($forecast_partial_month)
#   {
#     $months_ago = $dumpmonth_ord - &bb2i (&yyyymm2bb ($year, $month)) ;
#     if (($months_ago > 0) && ($months_ago <= 5))
#     {
#       if (&bbb2i (&ddhhmm2bbb ($day, $hour, $min)) < @partial_months [$months_ago])
#       {
#         if ($filesizelarge)
#         {
#           my $file_events_user_month_partial = $path_temp . "UserEditsPerMonthPartial~$yyyymm" ;
#           $file = @files_events_user_month_partial {$file_events_user_month_partial} ;
#           if ($file eq "")
#           {
#             $file = "UserEditsMonthPartial$yymm" ;
#             @files_events_user_month_partial {$file_events_user_month_partial} = $file ;
#             open $file, ">", $file_events_user_month_partial ;
#             binmode ($file) ;
#           }
#           print {$file} "$user\n" ;
#         }
#         else
#         { @edits_per_user_per_partial_month {$yymm . " " . $user} ++ ; }
#       }
#     }
#   }
# }

  if (! &NameSpaceArticle ($language, $namespace))
  { return ; }

# Dec 2016 redirects are no longer exluded from edit(or) ocunts, they are still for article counts
# if ($revision_is_redirect)
# { return ; }

  # remember first and last update for this user
  my $record = $userdata {$user} ;

# $useritem_id = 0 ;
# $useritem_edit_first = 1 ;
# $useritem_edit_last = 2 ;
# $useritem_edit_ip_namespace_a = 3 ;
# $useritem_edit_ip_namespace_x = 4 ;
# $useritem_edit_reg_namespace_a = 5 ;
# $useritem_edit_reg_namespace_x = 6 ;
# $useritem_edit_reg_recent_namespace_a = 7 ;
# $useritem_edit_reg_recent_namespace_x = 8 ;
# $useritem_create_reg_namespace_a = 9 ;
# $useritem_create_reg_namespace_x = 10 ;
# $useritem_create_reg_recent_namespace_a = 11 ;
# $useritem_create_reg_recent_namespace_x = 12 ;
# $useritem_edits_10 = 13 ;

  my @fields = split (',', $record) ;
  if (($record eq "") || ($fields [$useritem_edit_first] eq ""))
  {

    if ($time == 0)
    { print "\nTIME '$time' for user '$user' should not be 0\n" ; }
    # ignore redirect pages for this purpose
    # a database bug files moved pages under false date
    if ($record eq "")
    {
      $record = ",,,,,,,,,,,,#" ;
      my @fields = split (',', $record) ;
    }
    $fields [$useritem_edit_first] = $time ;
    $fields [$useritem_edit_last]  = $time ;
    $fields [$useritem_edits_10] = $time ;
    $userdata {$user} = join (',', @fields) ;
  }
  else
  {
    $userdata_dirty = $false ;
    if ($time < $fields [$useritem_edit_first])
    {
      # ignore redirect pages for this purpose
      # a database bug files moved pages under false date
      $fields [$useritem_edit_first] = $time ;
      $userdata_dirty = $true ;
    }
    if ($time > $fields [$useritem_edit_last])
    {
      $fields [$useritem_edit_last] = $time ;
      $userdata_dirty = $true ;
    }

    @edits_10 = split ('\|', $fields [$useritem_edits_10]) ;

    # less then 10 times stored -> add time
    if ($#edits_10 < 9)
    {
      $fields [$useritem_edits_10] .= "|$time" ;
      $userdata_dirty = $true ;
    }
    else
    {
      push @edits_10, $time ;
      @edits_10 = sort {$a <=> $b} @edits_10 ;
      if ($edits_10 [10] != $time)
      {
        pop @edits_10 ;
        $fields [$useritem_edits_10] = join ('|', @edits_10) ;
        $userdata_dirty = $true ;
      }
    }

    if ($userdata_dirty)
    { $userdata {$user} = join (',', @fields) ; }

    if ($fields [$useritem_edit_last] == 0)
    { print "USER $user USERDATA " . $userdata {$user} . "\n" ; }
  }
}

sub CollectArticleCounts
{
  my $current_revision = shift ;
  my $namespace = shift ;
  my $pageid    = shift ;
  my $article   = shift ;
  my $user      = shift ;
  my $userseqno    = shift ;
  my $time      = $time_gm ;
  my $revision_is_redirect = $false ;
  my $event ;
  my $size      = 0 ;
  my $size2     = 0 ;
  my $words     = 0 ;

  my $article_type = '-' ;
  my $skip_counts = $false ;
  if ($article eq "#@")
  { $skip_counts = $true ; }

  # only when full archive dump is processed check each revision for being a redirect
  # in stub dump there can be a <redirect /> attribute, determined by #REDIRECT (or other language equivalent) in last revision
  if ($edits_only)
  {
    # stub dump -> global flag in page xml for all revisions
    if ($edits_only_page_is_redirect)
    { $article_type = "R" ; }
    else
    { $article_type = "+" ; }
    
    if ($language eq 'wikidata') # count all pages
    { $article_type = '+' ; }
    
    $event = &i2bbbb ($pageid) . &t2bbbbb ($time) . $article_type . &i2bbbb (0) . &i2bbbb (0) .
             &i2bb (0) . &i2b (0) . &i2b (0) . &i2b (0) . &i2b (0) .
             &i2bbb (0) . &i2bbbb ($userseqno) . "\n" ;

    &WriteEvent ($event, $pageid, $time) ;
    $length_line_event = length ($event) ;

    return ($edits_only_page_is_redirect, $article_type) ;
  }

  # restore quotes
  $title   =~ s^\#\*\$\@^'^g ;

  $article =~ s^\#\*\$\@^'^g ;
  $article =~ s/\\r/\r/go ;
  $article =~ s/\\n/\n/go ;
  $article =~ s/\\"/"/go ;
  $size = length ($article) ;

  $links         = 0 ;
  $wikilinks     = 0 ;
  $imagelinks    = 0 ;
  $categorylinks = 0 ;
  $externallinks = 0 ;

  if (! $skip_counts)
  {
    # see http://svn.wikimedia.org/viewvc/mediawiki/trunk/phase3/includes/Title.php?view=markup
    # public static function newFromRedirect( $text )
    # for code that marks article as redirect

my $start_collect_articlecounts1 = code_started() if $record_time_collect_article_counts ;

    $revision_is_redirect = ($article =~ m/(?:$redirtag).*?\[\[.*?(?:\||\]\])/ios) ;

    if ($revision_is_redirect)
    { $article_type = "R" ; }
code_complete ("CollectArticleCounts1", $start_collect_articlecounts1) if $record_time_collect_article_counts ;

    if (! $revision_is_redirect)
    {

my $start_collect_articlecounts2 = code_started() if $record_time_collect_article_counts_main ;

      if ($article =~ m/\[\[/)
      {
        $article_type = "+" ;

        #  strip headers, wiki formatting, html
        $article2 = $article;

my $start_collect_articlecounts2a1 = code_started() if $record_time_collect_article_counts ;

        $article2 =~ s/\'\'+//go ; # strip bold/italic formatting
        $article2 =~ s/\<[^\>]+\>//go ; # strip <...> html

code_complete ("CollectArticleCounts2a1", $start_collect_articlecounts2a1) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2a2 = code_started() if $record_time_collect_article_counts ;

  #     $article2 =~  s/[\xc0-\xdf][\x80-\xbf]|
  #                     [\xe0-\xef][\x80-\xbf]{2}|
  #                     [\xf0-\xf7][\x80-\xbf]{3}/{x}/gxo ;
        $article2 =~  s/[\xc0-\xf7][\x80-\xbf]+/{x}/gxo ;

code_complete ("CollectArticleCounts2a2", $start_collect_articlecounts2a2) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2b = code_started() if $record_time_collect_article_counts ;

        $article2 =~ s/\&\w+\;/x/go ;   # count html chars as one char
        $article2 =~ s/\&\#\d+\;/x/go ; # count html chars as one char

code_complete ("CollectArticleCounts2b", $start_collect_articlecounts2b) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2c = code_started() if $record_time_collect_article_counts ;

        $article2 =~ s/\[\[ [^\:\]]+ \: [^\]]* \]\]//gxoi ; # strip image/category/interwiki links
                                                            # a few internal links with colon in title will get lost too
        $article2 =~ s/http \: [\w\.\/]+//gxoi ; # strip external links

        $article4 = $article2 ;

code_complete ("CollectArticleCounts2c", $start_collect_articlecounts2c) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2d = code_started() if $record_time_collect_article_counts ;

        $article2 =~ s/\{x\}/x/g ;
        $article2 =~ s/\=\=+ [^\=]* \=\=+//gxo ; # strip headers
        $article2 =~ s/\n\**//go ; # strip linebreaks + unordered list tags (other lists are relatively scarce)
        $article2 =~ s/\s+/ /go ; # remove extra spaces

code_complete ("CollectArticleCounts2d", $start_collect_articlecounts2d) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2e = code_started() if $record_time_collect_article_counts ;

        # calc length of stripped articles - internal links
        $length2 = length ($article2) ;
        $length3 = $length2 ;
        while ($article2 =~ /(\[\[ [^\]]* \]\])/gxo)
        { $length3 -= length ($1) ; }
        while ($article2 =~ /\[\[ ([^\]\|]* \|)? [^\]]* \]\]/gxo)
        { $length2 -= length ($1) ; }
        $size2 = $length2 ;

        if ($article eq "")
        { $article_type = "S" ; }
        elsif ($length2 < $length_stub) { $article_type = "S" ; } # stub

        $words = 0 ;
        $unicodes = 0 ;

code_complete ("CollectArticleCounts2e", $start_collect_articlecounts2e) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2f = code_started() if $record_time_collect_article_counts ;

        if ($ja_zh_ko)
        {
          while ($article4 =~ m/\{x\}/g)
          { $unicodes++ ; }
          if ($language eq "ja")
          { $words = int ($unicodes * 0.37) ; }
          else
          { $words = int ($unicodes * 0.55) ; }
          $article4 =~ s/(?:\{x\})+/ /g ;
        } # most unicodes are separate characters, each a word
        else
        { $article4 =~ s/\{x\}/x/g ; } # most unicodes are diacritical characters, part of one larger word

code_complete ("CollectArticleCounts2f", $start_collect_articlecounts2f) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2g = code_started() if $record_time_collect_article_counts ;

        $article4 =~ s/\d+[,.]\d+/number/g ; # count number as one word

code_complete ("CollectArticleCounts2g", $start_collect_articlecounts2g) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2h = code_started() if $record_time_collect_article_counts ;

        $article4 =~ s/\[\[ (?:[^|\]]* \|)? ([^\]]*) \]\]/$1/gxo ; # links -> text + strip hidden part of links

code_complete ("CollectArticleCounts2h", $start_collect_articlecounts2h) if $record_time_collect_article_counts ;
my $start_collect_articlecounts2i = code_started() if $record_time_collect_article_counts ;

      # while ($article4 =~ m/(?:(?>\w+\W+))/g)
        while ($article4 =~ m/\b\w+\b/g)
        { $words++ ; }

code_complete ("CollectArticleCounts2i", $start_collect_articlecounts2i) if $record_time_collect_article_counts ;
      }

code_complete ("CollectArticleCounts2", $start_collect_articlecounts2) if $record_time_collect_article_counts_main ;
my $start_collect_articlecounts3 = code_started() if $record_time_collect_article_counts_main ;

#my $start_collect_articlecounts3a = code_started() if $record_time_collect_article_counts ;

      undef (@links) ;
      $links = 0 ;
      while ($article =~ /\[\[([^\:\]]*)\]\]/go)
      { push @links, uc ($1) ; }
      while ($article =~ /\[\[[^\]]{2,3}:/go)
      { $wikilinks ++ ; }

#code_complete ("CollectArticleCounts3a", $start_collect_articlecounts3a) if $record_time_collect_article_counts ;

      while ($article =~ /\[\[([^\]]{4,}:[^\]]*)\]\]/go)
      {
#my $start_collect_articlecounts3b = code_started() if $record_time_collect_article_counts ;

        if (index (substr ($1,0,4),':') > 1)
        { $wikilinks ++ ; }
        else
        {
          my $a = $1 ;

#my $start_collect_articlecounts3c = code_started() if $record_time_collect_article_counts ;

          if ($a =~ /^(?:$imagetag)\:/io)
          {
            $imagelinks ++ ;
            if (! $prescan)
            {
              my $tag = lc ($a) ;
              $tag =~ s/^([^:]*):.*$/$1/s ;
              if ($imagetags {$tag} == 0)
              { &LogT ("\nNew image tag '" . encode_non_ascii ($tag) . "' encountered\n- ") ; }
              $imagetags {$tag}++ ;
            }
          }
          else
          {
#my $start_collect_articlecounts3d = code_started() if $record_time_collect_article_counts ;

            if ($a =~ /^(?:$categorytag)\:/gio)
            { $categorylinks ++ ; }
            else
            {
              if ($categorytag ne "category")
              {
                if ($a =~ /^category\:/gio)
                { $categorylinks ++ ; }
              }
            }
#code_complete ("CollectArticleCounts3d", $start_collect_articlecounts3c) if $record_time_collect_article_counts ;
          }
#code_complete ("CollectArticleCounts3c", $start_collect_articlecounts3b) if $record_time_collect_article_counts ;
        }
#code_complete ("CollectArticleCounts3b", $start_collect_articlecounts3a) if $record_time_collect_article_counts ;
      }

      @links = sort { $a cmp $b} @links ;
      $lprev = "@#$%" ;
      foreach $lcurr (@links)
      {
        if ($lcurr ne $lprev)
        { $links++ ; }
        $lprev = $lcurr ;
      }

#my $start_collect_articlecounts3e = code_started() if $record_time_collect_article_counts ;

      while ($article =~ m/(https?:)[^\s]+\./go) { $externallinks ++ ; }
      while ($article =~ m/(ftp:)[^\s]+\./go)    { $externallinks ++ ; }

#code_complete ("CollectArticleCounts3e", $start_collect_articlecounts3e) if $record_time_collect_article_counts ;
code_complete ("CollectArticleCounts3", $start_collect_articlecounts3) if $record_time_collect_article_counts_main ;

  #   $links = $links - $imagelinks - $categorylinks - $wikilinks ;

      # maximize values so that they fit into assigned byte space
      # theoretically this may not be enough for a tiny tiny fraction of counts
      # for the foreseeing future this is acceptable (less than 0.1% error)
      # minimizing memory usage weighs higher
      if ($wikilinks     > $bhi)  {$wikilinks     = $bhi ; }  # max 127
      if ($imagelinks    > $bhi)  {$imagelinks    = $bhi ; }  # max 127
      if ($categorylinks > $bhi)  {$categorylinks = $bhi ; }  # max 127
      if ($externallinks > $bhi)  {$externallinks = $bhi ; }  # max 127
      if ($links         > $b2hi) {$links         = $b2hi ; } # max 16,383
      if ($words         > $b3hi) {$words         = $b3hi ; } # max 2,097,151

      # article without html/wiki formatting etc contains over 50% links ?
      if ($length3 * 2 < $length2) # link list
      { $links = 0 ; }
    }
  }

  my $userseqno2 = $userseqno ;

  die ("\nOverflow: page id \$pageid can not be packed in 4 bytes!") if ($pageid > $b4hi) ;
  die ("\nOverflow: size \$size can not be packed in 4 bytes!") if ($size > $b4hi) ; # $size2 < $size

  # pack values into binary representation, use bytes 00-7F to avoid misinterpretation as unicode

  # i2bbbb -> range = 0 - 7F7F7F7F = 0 - 268,435,455
  # i2bbb  -> range = 0 - 7F7F7F   = 0 -   2,097,151
  # i2bb   -> range = 0 - 7F7F     = 0 -      16,383
  # i2b    -> range = 0 - 7F       = 0 -         127

#  &i2bbbb ($pageid) .         0,4
#  &t2bbbbb ($time) .          4,5
#  $article_type .             9,1
#  &i2bbbb ($size) .          10,4
#  &i2bbbb ($size2) .         14,4
#  &i2bb ($links) .           18,2
#  &i2b ($wikilinks) .        20,1
#  &i2b ($imagelinks) .       21,1
#  &i2b ($categorylinks) .    22,1
#  &i2b ($externallinks) .    23,1
#  &i2bbb ($words) .          24,3
#  &i2bbbb ($userseqno) ;        27,4
# reclen = 32

  if ((($mode eq "wb") || ($mode eq "wv")) && &NameSpaceArticle ($language, $namespace) && ($article !~ /(?:$redirtag)/i))  # strategy
  {
    if ($current_revision)
    {
      if ($article !~ /\{\{bereits nach de\.wikibooks\.org verschoben\}\}/)
      {
        $book_size  {$booktitle} += $size2 ;
        $book_words {$booktitle} += $words ;
      }
    }

    if (($userseqno % 2) == 0) # reg. user ?
    {
      $authors = $book_authors {$booktitle} ;
      if ($authors =~ /\{$userseqno\}/)
      { $authors =~ s/\{$userseqno\}\[(\d+)\]/"\{$userseqno\}\[".($1+1)."\]"/e ; }
      else
      { $authors .= "\{$userseqno\}[1]" }
      $book_authors {$booktitle} = $authors ;
    }
  }

  my $start_collect_articlecounts4 = code_started() if $record_time_collect_article_counts ;

  if ($language eq 'wikidata') # count all pages
  { $article_type = '+' ; }

  $bytes_raw_event = length ("$pageid $time $article_type $size $size2 $links $wikilinks $imagelinks $categorylinks $externallinks $words $userseqno2\n") ;

  $event = &i2bbbb ($pageid) . &t2bbbbb ($time) . $article_type . &i2bbbb ($size) . &i2bbbb ($size2) .
           &i2bb ($links) . &i2b ($wikilinks) . &i2b ($imagelinks) . &i2b ($categorylinks) . &i2b ($externallinks) .
           &i2bbb ($words) . &i2bbbb ($userseqno2) . "\n" ;
  $length_line_event = length ($event) ;

  if ($skip_counts)
  {
    $revision_is_redirect = $revision_is_redirect_prev ;
    $event    = $event_prev ;
    substr ($event, 4,5) = &t2bbbbb ($time) ;
    substr ($event,27,4) = &i2bbbb ($userseqno2) ;
  }
  $revision_is_redirect_prev = $revision_is_redirect ;
  $event_prev    = $event ;

  &WriteEvent ($event, $pageid, $time, $bytes_raw_event) ;
  code_complete ("CollectArticleCounts4", $start_collect_articlecounts4) if $record_time_collect_article_counts ;

  return ($revision_is_redirect, $article_type) ;
}

sub WriteEvent

{
  my $event = shift ;
  my $pageid = shift ;
  my $time  = shift ;
  my $bytes_raw_event = shift ;

  $tot_events++ ;

  $pageid = int ($pageid/10000) ;

  # since xml is now supposed to be sorted by article id, one file handle at a time open is enough
  # parsing English dump failed whne 2000 handles were open

  my $path_events_article = $path_temp . "EventsSortByArticle~".sprintf ("%05d", $pageid) ;
  my $file_events_article = $files_events_article {$path_events_article} ;

  if ($file_events_article eq "")
  {
    if ($file_events_article_prev ne "")
    { close $file_events_article_prev ; }

    $file_events_article = "EventsArticle" . $events_article++ ;
    $files_events_article {$path_events_article} = $file_events_article ;
    $file_events_article_prev = $file_events_article ;

    open $file_events_article, ">", $path_events_article ;
    binmode ($file_events_article) ;
    $file_opens_events_article ++ ;
  }
  elsif ($file_events_article ne $file_events_article_prev)
  {
    if ($file_events_article_prev ne "")
    { close $file_events_article_prev ; }

    $file_events_article_prev = $file_events_article ;

    open $file_events_article, ">>", $path_events_article ;
    binmode ($file_events_article) ;
    $file_opens_events_article ++ ;
  }

  print {$file_events_article} $event ;

  # return now for anonymous users
  my $user_seqno = &bbbb2i  (substr ($event,27,4)) ;
  if (($user_seqno % 2) == 1) # IP address ?
  { return ; }

  (my $month, my $year) = (localtime ($time))[4,5] ;

  my $path_events_month = $path_temp . "EventsSortByMonth~".sprintf ("%04d-%02d", $year + 1900, $month + 1) ;
  my $file_events_month = $files_events_month {$path_events_month} ;

  if ($file_events_month eq "")
  {
    $file_events_month = "EventsMonth" . $events_month++ ;
    $files_events_month {$path_events_month} = $file_events_month ;
    open $file_events_month, ">", $path_events_month ;
    binmode ($file_events_month) ;
  }
  print {$file_events_month} $event ;

  $total_bytes_raw_events        += $bytes_raw_event ;
  $total_bytes_compressed_events += length ($event) ;
}

sub ReadFileCsv
{
  my ($wp, $date, $day, $month, $year) ;
  my $file_csv = shift ;
  undef @csv  ;

  if (! -e $file_csv)
  { &LogT ("File $file_csv not found.\n") ; return ; }

  open FILE_IN, "<", $file_csv ;
  while ($line = <FILE_IN>)
  {
    if (! ($line =~ /^$language\,/))
    {
      chomp ($line) ;
      push @csv, $line ;
    }
  }
  close FILE_IN ;
}

sub ReadFileCsvAll
{
  my ($wp, $date, $day, $month, $year) ;
  my $file_csv = shift ;
  undef @csv  ;

  if (! -e $file_csv)
  { &LogT ("File $file_csv not found.\n") ; return ; }

  open FILE_IN, "<", $file_csv ;
  while ($line = <FILE_IN>)
  {
    chomp ($line) ;
    push @csv, $line ;
  }
  close FILE_IN ;
}

sub ReadFileCsvOnly
{
  my $file_csv = shift ;
  undef @csv  ;

  if (! -e $file_csv)
  { &LogT ("File $file_csv not found.\n") ; return ; }

  open FILE_IN, "<", $file_csv ;
  while ($line = <FILE_IN>)
  {
    if ($line =~ /^$language\,/)
    {
      chomp ($line) ;
      push @csv, $line ;
    }
  }
  close FILE_IN ;
}

sub ReadFileCsvExcept
{
  my ($file_csv,$language) = @_ ;
  undef @csv  ;

  if (! -e $file_csv)
  { &LogT ("File $file_csv not found.\n") ; return ; }

  open FILE_IN, "<", $file_csv ;
  while ($line = <FILE_IN>)
  {
    if ($line !~ /^$language\,/)
    {
      chomp ($line) ;
      push @csv, $line ;
    }
  }
  close FILE_IN ;
}

sub ReadAccessLevels
{
  &LogPhase ("ReadAccessLevels") ;

  if (! -e $file_in_sql_usergroups)
  { abort ("ReadAccesLevels \$file_in_sql_usergroups '$file_in_sql_usergroups' not found.\n") ; }

  if ($file_in_sql_usergroups =~ /\.gz$/)
  { open "GROUPS", "-|", "gzip -dc \"$file_in_sql_usergroups\"" || abort ("Input file '" . $file_in_sql_usergroups . "' could not be opened.") ; }
  elsif ($file_in_sql_usergroups =~ /\.bz2$/)
  { open "GROUPS", "-|", "bzip2 -dc \"$file_in_sql_usergroups\"" || abort ("Input file '" . $file_in_sql_usergroups . "' could not be opened.") ; }
  elsif ($file_in_sql_usergroups =~ /\.7z$/)
  { open "GROUPS", "-|", "./7za e -so \"$file_in_sql_usergroups\"" || abort ("Input file '" . $file_in_sql_usergroups . "' could not be opened.") ; }
  else
  { open "GROUPS", "<", $file_in_sql_usergroups || abort ("Input file '" . $file_in_sql_usergroups . "' could not be opened.") ; }

  binmode "GROUPS" ;

  while ($line = <GROUPS>)
  { $line =~ s/\(\d+,'(\w+)'\)/($access{$1}++)/ge ; }

  close "GROUPS" ;
}

sub ReadUserNamesWikiLovesMonuments
{
  # use this list of participants (in any year) to copy namespace 6
  &LogPhase ("ReadUserNamesWikiLovesMonuments") ;
  
  my $path_csv_wm = $path_out ;
  $path_csv_wm =~ s/csv_.*$/csv_mw/ ;
  my $year = 2010 ;
  my $file_participants_per_year = "$path_csv_wm/WLM_uploaders_$year.txt" ;

  if (! -d $path_csv_wm)
  { print "Dir $path_csv_wm not found\n" ; } 

  while (-e $file_participants_per_year)
  {
    print "Read $file_participants_per_year\n" ;

    open CSV_WLM, '<', $file_participants_per_year ;
    binmode CSV_WLM ;
    while ($line = <CSV_WLM>)
    {
      chomp $line ;
      $line =~ s/^\s*// ;
      $line =~ s/\s*$// ;
      if ($line !~ /^\s*$/)
      { $wiki_loves_monuments_participant {$line} ++ ;}
    }
    close CSV_WLM ;

    $year++ ;
    $file_participants_per_year = "$path_csv_wm/WLM_uploaders_$year.txt" ;
  }
  @wiki_loves_monuments_participant = keys %wiki_loves_monuments_participant ;
  print '' . ($#wiki_loves_monuments_participant + 1) . " participants found in all event files combined\n\n" ; # start with '' to avoid "print interpreted as a function"

  # foreach $name (sort {$wiki_loves_monuments_participant {$a} <=> $wiki_loves_monuments_participant {$b}} keys %wiki_loves_monuments_participant)
  # { print "$name: " . $wiki_loves_monuments_participant {$name} . "\n" ; }
}

sub ReadInputSqlFlaggedRevs
{
  $timestart_parse = time ;

  $Kb = 1024 ;
  $Mb = $Kb * $Kb ;

  # full caps = copy content
  $first = "\\(" ;               # find start of record = opening brace
  $TEXT  = "(NULL|'[^']*')," ; # alphanumeric field (save contents between quotes)
  $text2 = "'[^']*'," ;          # alphanumeric field
  $INT   = "(\\d+)," ;           # integer field (save contents)
  $int2  = "\\d+," ;             # integer field
  $FLOAT = "([^,]*)," ;          # used for floating point field
  $LAST  = "([^\)]*)\\)" ;       # last field and closing brace
  $last  = "[^\)]*\\)" ;         # last field and closing brace

# SET character_set_client = utf8;
# CREATE TABLE `page` (
#   `page_id` int(8) unsigned NOT NULL auto_increment,
#   `page_namespace` int(11) NOT NULL default '0',
#   `page_title` varchar(255) binary NOT NULL default '',
#   `page_restrictions` tinyblob NOT NULL,
#   `page_counter` bigint(20) unsigned NOT NULL default '0',
#   `page_is_redirect` tinyint(1) unsigned NOT NULL default '0',
#   `page_is_new` tinyint(1) unsigned NOT NULL default '0',
#   `page_random` double unsigned NOT NULL default '0',
#   `page_touched` varchar(14) binary NOT NULL default '',
#   `page_latest` int(8) unsigned NOT NULL default '0',
#   `page_len` int(8) unsigned NOT NULL default '0',
#   `page_no_title_convert` tinyint(1) NOT NULL default '0',
#   PRIMARY KEY  (`page_id`),
#   UNIQUE KEY `name_title` (`page_namespace`,`page_title`),
#   KEY `page_random` (`page_random`),
#   KEY `page_len` (`page_len`)
# ) TYPE=InnoDB;

  my $file_sql_pages = "W:/# In Dumps/dewiki-20100117-page.sql" ;
  my $file_csv_pages = "W:/# Out Test/csv_wp/PagesDe.csv" ;

  $reg_expr_pages = qr"$first$INT$INT$TEXT$TEXT$INT$INT$INT$FLOAT$TEXT$INT$INT$LAST" ;

# &ReadFileSql ($file_sql_pages, $file_csv_pages, $reg_expr_pages) ;

  &Log ("\n\nParsing SQL file $file_sql_pages took " . ddhhmmss (time - $timestart_parse). ".\n") ;

# SET character_set_client = utf8;
# CREATE TABLE `user` (
#   `user_id` int(5) unsigned NOT NULL auto_increment,
#   `user_name` varchar(255) binary NOT NULL default '',
#   `user_real_name` varchar(255) binary NOT NULL default '',
#   `user_password` tinyblob NOT NULL,
#   `user_newpassword` tinyblob NOT NULL,
#   `user_email` tinytext NOT NULL,
#   `user_options` blob NOT NULL,
#   `user_touched` varchar(14) binary NOT NULL default '',
#   `user_token` varchar(32) binary NOT NULL default '',
#   `user_email_authenticated` varchar(14) binary default NULL,
#   `user_email_token` varchar(32) binary default NULL,
#   `user_email_token_expires` varchar(14) binary default NULL,
#   `user_registration` varchar(14) binary default NULL,
#   `user_newpass_time` varchar(14) binary default NULL,
#   `user_editcount` int(11) default NULL,
#   PRIMARY KEY  (`user_id`),
#   UNIQUE KEY `user_name` (`user_name`),
#   KEY `user_email_token` (`user_email_token`)
# ) TYPE=InnoDB;

  my $file_sql_user = "W:/# In Dumps/dewiki-20100117-user.sql" ;
  my $file_csv_user = "W:/# Out Test/csv_wp/UserDe.csv" ;

  $reg_expr_user = qr"$first$INT$TEXT$last" ;

# &ReadFileSql ($file_sql_user, $file_csv_user, $reg_expr_user) ;

  &Log ("\n\nParsing SQL file $file_sql_user took " . ddhhmmss (time - $timestart_parse). ".\n") ;

# SET character_set_client = utf8;
# CREATE TABLE `flaggedpages` (
#   `fp_page_id` int(11) NOT NULL default '0',
#   `fp_reviewed` tinyint(1) NOT NULL default '0',
#   `fp_stable` int(11) default NULL,
#   `fp_quality` tinyint(1) default NULL,
#   `fp_pending_since` char(14) default NULL,
#   PRIMARY KEY  (`fp_page_id`),
#   KEY `fp_reviewed_page` (`fp_reviewed`,`fp_page_id`),
#   KEY `fp_quality_page` (`fp_quality`,`fp_page_id`),
#   KEY `fp_pending_since` (`fp_pending_since`)
# ) TYPE=InnoDB;

  my $file_sql_flagged_pages = "W:/# In Dumps/dewiki-20100117-flaggedpages.sql" ;
  my $file_csv_flagged_pages = "W:/# Out Test/csv_wp/FlaggedPagesDe.csv" ;

  $reg_expr_flagged_pages = qr"$first$INT$INT$INT$INT$LAST" ;

# &ReadFileSql ($file_sql_flagged_pages, $file_csv_flagged_pages, $reg_expr_flagged_pages) ;

  &Log ("\n\nParsing SQL file $file_sql_flagged_pages took " . ddhhmmss (time - $timestart_parse). ".\n") ;

# SET character_set_client = utf8;
# CREATE TABLE `flaggedrevs` (
#   `fr_page_id` int(11) NOT NULL default '0',
#   `fr_rev_id` int(11) NOT NULL default '0',
#   `fr_user` int(5) NOT NULL default '0',
#   `fr_timestamp` varchar(14) NOT NULL default '',
#   `fr_comment` mediumblob NOT NULL,
#   `fr_quality` tinyint(1) NOT NULL default '0',
#   `fr_tags` mediumblob NOT NULL,
#   `fr_text` mediumblob NOT NULL,
#   `fr_flags` tinyblob NOT NULL,
#   `fr_img_name` varchar(255) binary default NULL,
#   `fr_img_timestamp` varchar(14) default NULL,
#   `fr_img_sha1` varchar(32) binary default NULL,
#   PRIMARY KEY  (`fr_page_id`,`fr_rev_id`),
#   KEY `page_qal_rev` (`fr_page_id`,`fr_quality`,`fr_rev_id`),
#   KEY `key_timestamp` (`fr_img_sha1`,`fr_img_timestamp`)
# ) TYPE=InnoDB;

  my $file_sql_flagged_revs = "W:/# In Dumps/dewiki-20100117-flaggedrevs.sql" ;
  my $file_csv_flagged_revs = "W:/# Out Test/csv_wp/FlaggedRevsDe.csv" ;
  $reg_expr_flagged_revs = qr"$first$INT$INT$INT$TEXT$TEXT$INT$TEXT$TEXT$TEXT$TEXT$TEXT$LAST" ;

  &ReadFileSql ($file_sql_flagged_revs, $file_csv_flagged_revs, $reg_expr_flagged_revs) ;

  &Log ("\n\nParsing SQL file $file_sql_flagged_revs took " . ddhhmmss (time - $timestart_parse). ".\n") ;
}

sub ReadFileSql
{
  my ($file_sql, $file_csv, $reg_exp) = @_ ;

  if ($file_sql =~ /\.gz$/)
  { open FILE_SQL, "-|", "gzip -dc \"$file_sql\"" || abort ("Input file " . $file_sql . " could not be opened.") ; }
  elsif ($file_sql =~ /\.bz2$/)
  { open FILE_SQL, "-|", "bzip2 -dc \"$file_sql\"" || abort ("Input file " . $file_sql . " could not be opened.") ; }
  else
  { open FILE_SQL, "<", $file_sql || abort ("Input file " . $file_sql . " could not be opened.") ; }

  open FILE_CSV, '>', $file_csv || abort ("Output file " . $file_csv . " could not be opened.") ;

  binmode FILE_SQL ;
  binmode FILE_CSV ;

  $filesize = -s $file_sql ;
  $fileage  = -M $file_sql ;

  if ($filesize == 0)
  { abort ("Input file " . $file_sql . " is empty.") ; }

  &Log ("\nRead sql dump file \'" . $file_sql . "\' (". &i2KbMb ($filesize) . ")\n") ;

  &Log ("Data read (Mb):\n") ;
  &LogTime ;

  my $file_completely_parsed = $false ;
  my $records_read = 0 ;
  while (($line = <FILE_SQL>) && ($line !~ /INSERT INTO/))
  { ; }

  $bytes_read = 0 ;
  $mb_read = 0 ;
  $records_read += &ProcessSqlBlock ($reg_exp) ;
  while (($line = <FILE_SQL>)  && (length ($line) > 1))
  {
    if ($line =~ /^UNLOCK TABLES;/i)
    { $file_completely_parsed = $true ; last }
    $records_read += &ProcessSqlBlock ($reg_exp) ;
  }
  close FILE_CSV ;
  close FILE_SQL ;

  if ($records_read == 0)
  {
    $file_sql =~ s/.*[\\\/]//g ;
    abort ("No records matched regexp in file '" . $file_sql . "'. File empty? Database layout changed?") ;
  }
  &Log ("\n\nRecords read: $records_read\n") ;
}

sub ProcessSqlBlock
{
  $reg_exp = shift ;

  #temporary replace all \' text quotes, leaving only CSV quotes
  $line =~ s/\\\'/\#\*\$\@/g ;
  $records_found = 0 ;

  undef @fields ;
  while ($line =~ m/$reg_exp/g)
  {
# $+ returns whatever the last bracket match matched
# $& returns the entire matched string
# $` returns everything before the matched string
# $' returns everything after the matched string.
    $records_found++ ;
    $output  = $1 ;
    $output .= defined ($2)  ? ($x= $2,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($3)  ? ($x= $3,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($4)  ? ($x= $4,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($5)  ? ($x= $5,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($6)  ? ($x= $6,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($7)  ? ($x= $7,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($8)  ? ($x= $8,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($9)  ? ($x= $9,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($10) ? ($x=$10,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($11) ? ($x=$11,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($12) ? ($x=$12,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($13) ? ($x=$13,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($14) ? ($x=$14,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($15) ? ($x=$15,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($16) ? ($x=$16,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($17) ? ($x=$17,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($18) ? ($x=$18,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($19) ? ($x=$19,$x=~s/,/;/g,",$x") : '';
    $output .= defined ($10) ? ($x=$20,$x=~s/,/;/g,",$x") : '';
    $output =~ s/\#\*\$\@/\\\'/g ;
    print FILE_CSV "$output\n" ;
  #  if ($output =~ /^1,/)
  #  { print "$output\n" ;
  #  print "XXX $+\n" ;
  #  print "XXX $&\n" ;
  #  print "XXX $`\n" ;
  #  }
  }

  $bytes_read += length ($line) ;
  while ($bytes_read > ($mb_read + 10) * $Mb)
  {
    ($min, $hour) = (localtime (time))[1,2] ;
    if ($prev_min ne $min)
    {
      &TraceMem ;
      &LogTime ;
      &Log ("\n - ") ;
      $prev_min = $min ;
    }

    &Log (($mb_read += 10) . " ") ;
  }
  return ($records_found) ;
}

sub ProcessSqlBlockComplete
{
  $reg_expr = shift ;

  #temporary replace all \' text quotes, leaving only CSV quotes
  $line =~ s/\\\'/\#\*\$\@/g ;
  $records_found = 0 ;
  while ($line =~ m/$reg_expr/g)
  {

    $records_found++ ;
    $recid     = $1 ;
    $namespace = $2 ;
    $title     = $3 ;
    $article   = $4 ;
    $user      = $5 ;
    $time      = $6 ;
    $flags     = $7 ;

    if ($time == 0) { next ; } # found invalid record in ja:

    ($year,$month,$day,$hour,$min,$sec) = $time =~ m/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ ;

    $time_gm    = timegm ($sec, $min, $hour, $day, $month-1, $year-1900) ;

    if ($time_gm <= $dumpdate_gm_hi)
    {
      if ($namespace == 0)
      {
        $yymm  = sprintf ("%02d%02d", $year - 2000, $month, ) ;
        $edits_per_month {$yymm} ++ ;

        if (not defined ($first_edit))
        { $first_edit = $time_gm ; }
        elsif ($time_gm < $first_edit)
        { $first_edit = $time_gm ; }
      }

      # restore quotes
      $user   =~ s^\#\*\$\@^'^g ;
      $userseqno = $users {$user} ;
      if (! defined ($userseqno))
      {
        $userseqno = ++ $cnt_users ;
        $users {$user} = $userseqno ;
        $users_id {$userseqno} = $user ;
      }
    }
  }

  $bytes_read += length ($line) ;
  while ($bytes_read > ($mb_read + 10) * $Mb)
  {
    ($min, $hour) = (localtime (time))[1,2] ;
    if ($prev_min ne $min)
    {
      &TraceMem ;
      &LogTime ;
      &Log (" - ") ;
      $prev_min = $min ;
    }

    &Log (($mb_read += 10) . " ") ;
  }
  return ($records_found) ;
}

sub TraceFlaggedRevs
{
  my ($id_page, $id_page_found, $id_rev, $timestamp, $ignore_from_date, @reviews) ;

  $id_page = shift ;

  my $file_csv_flagged_revs = "W:/# Out Test/csv_wp/FlaggedRevsDe.csv" ;
  my $file_csv_user         = "W:/# Out Test/csv_wp/UserDe.csv" ;
  my $file_csv_pages        = "W:/# Out Test/csv_wp/PagesDe.csv" ;
  my $file_xml_stubs        = "W:/# In Dumps/dewiki-20100117-stub-meta-history.xml" ;

  ($ignore_from_date = $file_xml_stubs) =~ s/^.*?(\d{8}).*$/$1/ ;
  $ignore_from_date = substr ($ignore_from_date,0,4) . '-' . substr ($ignore_from_date,4,2) . '-' . substr ($ignore_from_date,6,2) ;
  &Log ("Ignore updates from start of $ignore_from_date (day when dump job started)\n") ;

  open PAGES, '<', $file_csv_pages ;
  while ($line = <PAGES>)
  {
    next if $line lt "$ifpage," ;
    last if $line !~ /^$id_page,/ ;
    chomp $line ;
    ($article_name = $line) =~ s/^\d+,\d+,'([^,]*)',.*$/$1/ ;
  }
  close PAGES ;

  open FLAGGED_REVS, '<', $file_csv_flagged_revs ;
  while ($line = <FLAGGED_REVS>)
  {
    next if $language eq 'de' and $line =~ /^1,1,/ ; # invalid record
    next if $line lt "$id_page," ;
    last if $line !~ /^$id_page,/ ;

    ($user = $line) =~ s/^\d+,\d+,(\d+),.*$/$1/ ;
    $users_flagged_revs {$user} ++ ;
    push @flagged_revs, $line ;
  }
  close FLAGGED_REVS ;

  open USERS, '<', $file_csv_user ;
  while ($line = <USERS>)
  {
    ($user = $line) =~ s/^(\d+),.*$/$1/ ;
    if ($users_flagged_revs {$user} > 0)
    {
      chomp $line ;
      ($user = $line) =~ s/^(\d+),.*$/$1/ ;
      ($user_name = $line) =~ s/^\d+,'([^',]*)'.*$/$1/ ;
      $user_name =~ s/,/&comma;/g ;
      $users_flagged_revs {$user} = $user_name ;
    }
  }
  close USERS ;

  undef @reviews ;
  foreach $line (@flagged_revs)
  {
    chomp $line ;
    my @fields = split (',', $line) ;
    $fields [0] = $article_name ;
    $fields [2] = $users_flagged_revs {$fields [2]} ;
    my $time = $fields [3] ;
    $time =~ s/'//g ;
    $fields [3] = substr ($time,0,4) . '-' . substr ($time,4,2) . '-' . substr ($time,6,2) . 'T' . substr ($time,8,2) . ':' . substr ($time,10,2) . ':' . substr ($time,12,2) . 'Z' ;
    unshift @fields, splice (@fields,3,1) ;
    $line = join ',', @fields ;
    print "LINE $line\n" ;
    push @reviews, $line ;
  }

  $review_needed_since = '' ;
  die "File '$file_xml_stubs' not found." if ! -e $file_xml_stubs ;
  open FILE_IN, '<', $file_xml_stubs || abort ("File '$file_xml_stubs' could not be opened.") ;
  binmode FILE_IN ;
  &XmlReadUntil ('(?:<page>|<\/mediawiki>)') ;
  while ($line =~ /<page>/)
  {
    $pages_read ++ ;
    &XmlReadUntil ('<id>') ;

    ($id_page_found = $line) =~ s/^.*?<id>([^<]*)<.*$/$1/g ;
    last if $id_page_found > $id_page ;
    &Log ("id: $id_page_found\n") ;

    if ($id_page_found == $id_page)
    {
      ($time_review,$title,$id_rev_review,$reviewer,$flags) = &GetNextReview (\@reviews, $ignore_from_date) ;

      &XmlReadUntil ('(?:<revision>|<\/page>)') ;
      while ($line =~ /<revision>/)
      {
        &XmlReadUntil ('<id>') ;
        ($id_rev_edit = $line) =~ s/^.*?<id>([^<]*)<.*$/$1/g ;

        &XmlReadUntil ('<timestamp>') ;
        ($time_edit = $line) =~ s/^.*?<timestamp>([^<]*)<.*$/$1/g ;

        &XmlReadUntil ('(?:<contributor>|<\/revision>)') ;
        
	if ($line =~ /<contributor>/)
        {
          &XmlReadUntil ('(?:<ip>|<username>|<\/revision>)') ;
          $user = '' ;
          if ($line =~ /<ip>/)
          { ($user = $line) =~ s/^.*?<ip>([^<]*)<.*$/ip:$1/g ; }
          if ($line =~ /<username>/)
          { ($user = $line) =~ s/^.*?<username>([^<]*)<.*$/$1/g ; }

          while (($time_review lt $time_edit) && ($time_review ne ''))
          {
            $reviewed_after_seconds = yyyymmddThhmmssDiff ($time_review, $review_needed_since) ;
            $reviewed_after_ddhhmmss = sprintf ("%-6s", $reviewed_after_seconds) ;
            $review_needed_since = '' ;
            &Log ("- R $reviewed_after_ddhhmmss $time_review,$id_rev_review,$reviewer,$flags\n") ;
            ($time_review,$title,$id_rev_review,$reviewer,$flags) = &GetNextReview (\@reviews, $ignore_from_date) ;
          }

          if (($id_rev_edit ne $id_rev_review) && ($time_edit ne $time_review))
          {
            $reviewed_after_ddhhmmss = sprintf ("%-6s", '') ;
            &Log ("E - $reviewed_after_ddhhmmss $time_edit,$id_rev_edit,$user\n") ;
            if ($review_needed_since eq '')
            { $review_needed_since = $time_edit ; }
          }
          else
          {
            $reviewed_after_seconds = '0' ;
            if ( $review_needed_since ne '')
            {
              $reviewed_after_seconds = yyyymmddThhmmssDiff ($time_review, $review_needed_since) ;
              $review_needed_since = '' ;
            }
            $reviewed_after_ddhhmmss = sprintf ("%-6s", '') ;
            &Log ("E A $reviewed_after_ddhhmmss $time_edit,$id_rev_edit,$user,$flags\n") ;
            ($time_review,$title,$id_rev_review,$reviewer,$flags) = &GetNextReview (\@reviews, $ignore_from_date) ;
          }
        }
        
        &XmlReadUntil ('<sha1') ;
	if ($line !~ /<\/sha1>/)
	{ $sha1 = '' ; } # 2014-06-17 test in DetectReverts for empty string instead of 0 
	else
	{ ($sha1 = $line) =~ s/^.*?<sha1>([^<]*)<.*$/$1/g ; }
        
	&XmlReadUntil ('(?:<revision>|<\/page>)') ;
      }
    }

    &XmlReadUntil ('(?:<page>|<\/mediawiki>)') ;
  }

  while ($time_review ne '')
  {
    $reviewed_after_seconds = yyyymmddThhmmssDiff ($time_review, $review_needed_since) ;
    $review_needed_since = '' ;
    $reviewed_after_ddhhmmss = sprintf ("%-6s", $reviewed_after_seconds) ;
    &Log ("- R $reviewed_after_ddhhmmss $time_review,$id_rev_review,$reviewer\n") ;
    ($time_review,$title,$id_rev_review,$reviewer,$flags) = &GetNextReview (\@reviews, $ignore_from_date) ;
  }

  close FILE_IN ;
  &Log ("Ready\n") ;
}

sub GetNextReview
{
  my $reviews = shift ;
  my $ignore_from_date =  shift ;
  my ($time_review,$title,$id_rev_review,$reviewer,$flags) ;

  if (scalar @$reviews > 0)
  {
    $review = shift @$reviews ;
    if ($review =~ /^\d\d\d\d-\d\d-\d\dT/)
    { ($time_review,$title,$id_rev_review,$reviewer,$d1,$d2,$d3,$d4,$flags) = split ',' , $review ; }
    if ($time_review ge substr ($ignore_from_date,0,8))
    { $time_review = '' ; }
  }
  return ($time_review,$title,$id_rev_review,$reviewer,$flags) ;
}

sub GetContentNamespaces
{
  undef %content_namespace ;
  
  if (! $base_content_namespaces_on_api)
  {  
    &LogT ("Use fixed namespaces for counting, not namespaces collected via api\n\n") ; 
    return ;
  }
  &LogT ("GetContentNamespaces\n") ;
  	
  my ($mode,$language) = @_ ;

  if (($mode eq '') || ($language eq ''))
  { abort "GetContentNamespaces: invalid arguments mode '$mode' language '$language'" ; } 

  my $project ;

  if (! -e $file_csv_content_namespaces)
  { abort ("Namespaces file not found: '$file_csv_content_namespaces'.\n>> Run 'collect_countable_namespaces.sh' <<") ; }

    my $language2 = $language ;
    $language2 =~ s/_/-/g ; # wikistats (unfortunately) uses codes like 'roa_rup', not 'roa-rup' , to be changed some day

    $line_content_namespaces = '' ;
    open FILE_NS, "<", $file_csv_content_namespaces ;
    while ($line = <FILE_NS>)
    {
      if ($line =~ /^$mode\,$language2\,/)
      {
        chomp ($line) ;
        $line_content_namespaces = $line ;
        last ;
      }
    }
    close FILE_NS ;

    if ($line_content_namespaces ne '')
    {
      &LogT ("Read content namespaces from file '$file_csv_content_namespaces': line='$line_content_namespaces'\n") ;
      my ($dummy_mode,$dummy_language,$content_namespaces) = split (',', $line_content_namespaces) ;
      foreach $id (split '\|', $content_namespaces)
      { $content_namespace {$id} = $true ; }
      &LogT ("Content namespaces for language $language: " . join (',', sort keys %content_namespace) . "\n") ;
    }
    else
    { abort("No entry found in namespaces file '$file_csv_content_namespaces' for project '$mode' language '$language2'.\n>> Run 'collect_countable_namespaces.sh' <<\n" .
	    "If that doesn't help manually add line with just namespace 0 in namespaces file, or remove obsolete '../csv/csv_$mode/EditsPerUserPerMonthPerNamespaceXXX.csv (where XXX is language code)\n") ; }
# }

  $namespaces_initialized = $true ;
}

sub FetchWebPage
{
  my $url = shift ;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Wikistats count job");
  $ua->timeout(60);

  my $req = HTTP::Request->new(GET => $url);
  $req->referer ("http://www.wikipedia.org");

  my $success = $false ;
  my $content = "" ;

  my $response = $ua->request($req);
  if ($response->is_error())
  {
    &LogT ("\nWeb page could not be fetched:\n  '$url'\nReason: '"  . $response->status_line . "'\n\n") ;
    return ('') ;
  }
  else
  {
    my $content = $response->content();
    $content =~ s/&lt;/</g ;
    $content =~ s/&gt;/>/g ;
    $content =~ s/&quot;/'/g ;

    if ($content !~ /MediaWiki API Result/i)
    { &LogT ("\nPage does not contain valid data:\n  '$url'\n") ; }
    elsif ($content !~ m/<\/html>/i)
    { &LogT ("\nPage is incomplete:\n  '$url'\n") ; }
    else
    { $success = $true ; }

    if (! $success )
    { return ('') ; }

    return ($content) ;
  }
}
1;
