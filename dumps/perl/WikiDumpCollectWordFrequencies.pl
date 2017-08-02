#!/usr/bin/perl
use CGI qw(:all);

  $max_titles = 999999999999 ; # 1000 ;
  $time_start = time ;

  $Kb = 1024 ;
  $Mb = $Kb * $Kb ;

  $true = 1 ;
  $false = 0 ;
  $production_run = $true ;

  $language = "en" ;

# to do: use cmd line arguments
  if ($production_run)
  {
    $dir_in   = "/mnt/data/xmldatadumps/public/enwiki/20141008/" ;
    $dir_out  = "/a/wikistats_git/dumps/tmp/" ;
    $basename = "enwiki-20141008-pages-meta-current" ;
  }
  else
  {
    $dir_in   = "W:/# In Dumps/" ;
    $dir_out  = "W:/# Out Test/" ;
    $basename = "simplewiki-20140927-pages-meta-current" ;
  }

  $file_in                                       = $dir_in  . $basename. ".xml" ;
  $file_freq_words_per_title                     = $dir_out . $basename . "_freq_words_per_title.txt" ;
  $file_freq_words_per_title_per_category        = $dir_out . $basename . "_freq_words_per_title_per_category.txt" ;
  $file_freq_words_per_title_per_category_sorted = $dir_out . $basename . "_freq_words_per_title_per_category_sorted.txt" ;
  $file_freq_words_per_category                  = $dir_out . $basename . "_freq_words_per_category.txt" ;
  $file_freq_words_all_titles                    = $dir_out . $basename . "_freq_words_all_titles.txt" ;
  $file_freq_categories                          = $dir_out . $basename . "_freq_categories.txt" ;
  $file_word_scores_per_category                 = $dir_out . $basename . "_word_scores_per_category.txt" ;

  if ($production_run)
  { $file_in .= ".bz2" ; }

  if (! -e $file_in)   { print "File $file_in not found."   ; exit ; }

  $| = 1; # flush screen output

# &Count ; # word counts per article
  &Map ;   # word counts per article per category
# &Sort ;  # sort by category
# &Merge ; # word counts by category
# &Score ;

  print "\nReady\n" ;
  exit ;

sub Count
{
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

  open FILE_FREQ_PER_TITLE,  ">", $file_freq_words_per_title  || abort ("Output file '" . $file_freq_words_per_title .  "' could not be opened.") ;
  open FILE_FREQ_ALL_TITLES, ">", $file_freq_words_all_titles || abort ("Output file '" . $file_freq_words_all_titles . "' could not be opened.") ;
  open FILE_FREQ_CATEGORIES, ">", $file_freq_categories       || abort ("Output file '" . $file_freq_categories      .  "' could not be opened.") ;

  binmode FILE_IN ;
  binmode FILE_FREQ_PER_TITLE ;
  binmode FILE_FREQ_ALL_TITLES ;
  binmode FILE_FREQ_CATEGORIES ;

  print FILE_OUT "title,categories, frequencies\n" ;

  $filesize = -s $file_in ;
  print "Read xml dump file \'" . $file_in . "\' (". sprintf ("%.1f", $filesize/$Mb) . " Mb)\n\n" ;

  $copy = 1 ;
  while ($line = <FILE_IN>)
  {
    next if $line =~ /^#/ ;
    # show progress in MB read
    $bytes_read += length ($line) ;
    while ($bytes_read > ($mb_read + 1) * $Mb)
    {
      $mb_read = sprintf ("%.0f", $bytes_read / $Mb) ;
      $show_unique_words = (++ $show_unique_words) % 50 ;
      if ($show_unique_words == 0)
      {
        $unique_words = 0 ;
        foreach $word (keys %overall_freq)
        { $unique_words++ ; }

        if ($time_start != time)
        {
          $run_time_sec = time - $time_start ;
          if ($run_time_sec != 0)
          { $titles_per_sec = sprintf ("%.0f", $titles / $run_time_sec) ; }
        }
        print &Comma ($mb_read) . " MB [" . sprintf ("%6s", "+" . ($titles-$titles_prev)) . " titles] " . &Comma($run_time_sec) . " sec, " .
               &Comma($titles) . " titles (" . &Comma ($titles_per_sec) . "/sec)) -> " . &Comma ($unique_words) . " unique words\n" ;
      }
      elsif ($show_unique_words % 10 == 0)
      { print &Comma($mb_read) . " MB [" . sprintf ("%6s", "+" . ($titles-$titles_prev)) . " titles]\n" ; }
      $titles_prev = $titles ;
    }

    if ($line =~ /<page>/)
    { $copy = $false ; $intext = $false ; }

    if ($line =~ /<namespace key="14">/)
    {
      $namespace_14 = $line ;
      chomp ($namespace_14) ;
      $namespace_14 =~ s/^.*?>(.*?)<.*$/$1/ ;
      print "Namespace 14 = '$namespace_14'\n\n" ; # prefix for categories is language dependant
    }

    if ($line =~ /<title>/)
    {
      $titles ++ ;
      last if ++$titles > $max_titles ;

      chomp ($line) ;
      $title = $line ;
      $title =~ s/^.*?>(.*?)<.*$/$1/ ;
      $category = ($title =~ /^$namespace_14\:/i) ;
#     $main_namespace = ($title !~ /\:/) ; # quick and dirty: sometimes : ocurs in namespace 0 article
      $main_namespace = ($title =~ /^[^:]+$/i) ;
      $copy = ($main_namespace || $category) ;
      $title =~ s/\s/_/g ;
#     if ($copy)
#     { print FILE_OUT "  <page>\n" ; }
    }

    if ($line =~ /<text[^\>]*>/)
    {
      $intext = $true ;
      $article = $line ;
      $article =~ s/^.*<text[^\>]*>// ;
      if ($article =~ /<\/text>/)
      {
        $article =~ s/<\/text.*$// ;
        $intext = $false ;

        &Analyse ($title,$article) ;
      }
    }
    elsif ($intext & $main_namespace)
    {
      $article .= $line ;
      if ($line =~ /<\/text>/)
      {
        $intext = $false ;

        $article =~ s/<\/text.*$// ;

        $article =~ s/__\w+__//gso ; # strip directives like __NOTOC__
        $article =~ s/\&lt;/</gs ;
        $article =~ s/\&gt;/>/gs ;
        $article =~ s/\&quot;/'/gs ;
        $article =~ s/\&amp;/\&/gs ;
        $article =~ s/\'\'+//gso ; # strip bold/italic formatting
        $article =~ s/<math>.*?<\/math>//gso ; # strip math formula's
        $article =~ s/<[^>]+>//gso ; # strip <...> html
        $article =~ s/\{\|.*?\|\}//gso ; # strip tables (????????????)
        $article =~ s/\{\{.*?\}\}//gso ; # strip templates (????????????)
#       $article =~ s/\[\[ [^\:\]]+ \: [^\]]* \]\]//gsxoi ; # strip image/category/interwiki links
                                                            # a few internal links with colon in title will get lost too
        $article =~ s/https? \: [\w\.\/]+//gsxoi ; # strip external links
#       $article =~ s/\n\**//go ; # strip linebreaks + unordered list tags (other lists are relatively scarce)
#       $article =~ s/\s+/ /go ; # remove extra spaces
#       $article =~ s/\[\[ (?:[^|\]]* \|)? ([^\]]*) \]\]/$1/gsxo ; # links -> text + strip hidden part of links

#       print FILE_TST "$article\n" ;
#print "$article\n" ;
        if (($title !~ /talk:/i) && ($title !~ /user:/i) && ($article !~ /#REDIRECT/i))
        { &Analyse ($title,$article) ; }
      }
    }
  }

  foreach $word (sort {$overall_freq  {$b} <=> $overall_freq {$a}} keys %overall_freq)
  { print FILE_FREQ_ALL_TITLES "$word," . $overall_freq{$word} . "\n" ; }

  foreach $category (sort {$category_freq {$b} <=> $category_freq {$a}} keys %category_freq)
  { print FILE_FREQ_CATEGORIES "$category," . $category_freq{$category} . "\n" ; }

  close FILE_IN ;
  close FILE_FREQ_PER_TITLE ;
  close FILE_FREQ_ALL_TITLES ;
  close FILE_FREQ_CATEGORIES ;
}

sub Analyse
{
  my ($title,$article) = @_ ;

  my %word_freq ;

  my $article2 = $article ;

  my @categories ;
  $title =~ s/,/\%2C/g ;

  $article2 =~ s/\n/ /g ;
  $article2 =~ s/\[\[category\:([^\]]*)\]\]/push @categories,$1/gie ;

  foreach $category (@categories)
  {
    $category =~ s/\|.*$//g ; # pipe with category -< sort order
    $category =~ s/^\s+//g ;  # leading spaces
    $category =~ s/\s+$//g ;  # trailing spaces
    $category =~ s/\s/_/g ;   # spaces -> underscores

    $category_freq {$category} ++ ;
  }


  $categories = join ('|', @categories) ;
  if ($categories eq '')
  { $categories = '-' ; }
# print "categories: $categories\n" ;

  $article2 =~ s/([a-zA-Z\x80-\xFF]{2,})/(@word_freq{lc($1)}++,"")/gse ;
# $article2 =~ s/([0-9][0-9]+)/(($a=$1,$a =~ m#^\d\d\d\d?$#) ? @cnt2{$a}++:"","x")/gse ; # only year numbers

  my $wordlist = '' ;
  foreach $word (sort {$word_freq {$b} <=> $word_freq {$a}} keys %word_freq)
  {
    $overall_freq {$word} += $word_freq {$word} ;

    $word2 = $word ;
    $word2 =~ s/\|/\%7C/g ;
    $wordlist .= "$word2:" . $word_freq {$word} . "|" ;
  }
  $wordlist =~ s/\|$// ;

  print FILE_FREQ_PER_TITLE "$title,$categories,$wordlist\n" ;
}

sub Map
{
  open FILE_FREQ_PER_TITLE,               "<", $file_freq_words_per_title               || abort ("Input file '" .  $file_freq_words_per_title .               "' could not be opened.") ;
  open FILE_FREQ_PER_TITLE_PER_CATEGORY,  ">", $file_freq_words_per_title_per_category  || abort ("Output file '" . $file_freq_words_per_title_per_category .  "' could not be opened.") ;

  binmode FILE_FREQ_PER_TITLE ;
  binmode FILE_FREQ_PER_TITLE_PER_CATEGORY ;

  while ($line = <FILE_FREQ_PER_TITLE>)
  {
    next if $line =~ /^#/ ;
    chomp $line ;
    my ($title,$categories,$wordlist) = split (',', $line) ;
    foreach $category (split '\|', $categories)
    { print FILE_FREQ_PER_TITLE_PER_CATEGORY "$category,$wordlist\n" ; }
  }

  close FILE_FREQ_PER_TITLE ;
  close FILE_FREQ_PER_TITLE_PER_CATEGORY ;
}

sub Sort
{
  my $cmd = "c:/gnuwin32/bin/sort -d -o \"$file_freq_words_per_title_per_category_sorted\" \"$file_freq_words_per_title_per_category\"" ;
  print "cmd = \"$cmd\"\n" ;
  $result = `$cmd` ;
  print "result = $result'\n" ;
}

sub Merge
{
  open FILE_FREQ_PER_TITLE_PER_CATEGORY,  "<", $file_freq_words_per_title_per_category_sorted  || abort ("Input file '"  . $file_freq_words_per_title_per_category_sorted .  "' could not be opened.") ;
  open FILE_FREQ_PER_CATEGORY,            ">", $file_freq_words_per_category                   || abort ("Output file '" . $file_freq_words_per_category                  .  "' could not be opened.") ;

  binmode FILE_FREQ_PER_TITLE_PER_CATEGORY ;
  binmode FILE_FREQ_PER_CATEGORY ;

  my $category_prev = '' ;
  my ($wordlist_in, $wordlist_out, %wordfreq) ;
  my  $tuples_qualified = $false ;

  while ($line = <FILE_FREQ_PER_TITLE_PER_CATEGORY>)
  {
    next if $line =~ /^#/ ;

    chomp $line ;
    my ($category,$wordlist_in) = split (',', $line) ;
    next if $category eq '-' ;

    if (($category ne $category_prev) && ($category_prev ne '') && $tuples_qualified)
    {
      $wordlist_out = '' ;
      $total_words = 0 ;
      foreach $word (sort { $wordfreq {$b} <=> $wordfreq {$a}} keys %wordfreq)
      {
        $wordlist_out .= "$word:" . $wordfreq {$word} . "|" ;
        $total_words += $wordfreq {$word} ;
      }
      $wordlist_out =~ s/\|$// ;
      if ($total_words > 0)
      { print FILE_FREQ_PER_CATEGORY "$category_prev,$total_words,$wordlist_out\n" ; }

      undef %wordfreq ;

      if (++ $categories_merged % 1000 == 0)
      { print "Categories merged: $categories_merged\n" ; }
    # print "$category\n" ;
    }

    foreach $tuple (split '\|', $wordlist_in)
    {
      ($word,$count) = split (':', $tuple) ;
      next if $word eq '' ;
      # next if $count < 10 ;
      $tuples_qualified = $true ;
      $wordfreq {$word} += $count ;
    # print "tuple $tuple, word $word, count $count\n" ;
    }

    $category_prev = $category ;
  }

  $total_words = 0 ;
  foreach $word (sort { $wordfreq {$b} <=> $wordfreq {$a}} keys %wordfreq)
  {
    $wordlist_out .= "$word:" . $wordfreq {$word} . '|' ;
    $total_words += $wordfreq {$word} ;
  }
  $wordlist_out =~ s/\|//g ;
  if ($total_words > 0)
  { print FILE_FREQ_PER_CATEGORY "$category_prev,$total_words,$wordlist_out\n" ; }

  print "Categories merged: $categories_merged\n" ;

  close FILE_FREQ_PER_TITLE_PER_CATEGORY ;
  close FILE_FREQ_PER_CATEGORY ;
}

sub Score
{
  open FILE_FREQ_ALL_TITLES, "<", $file_freq_words_all_titles || abort ("Input file '" . $file_freq_words_all_titles . "' could not be opened.") ;
  binmode FILE_FREQ_ALL_TITLES ;

  my %wordfreq_all_titles ;
  my $words_total = 0 ;
  my $words_unique = 0 ;
  my $lines = 0 ;
  my %scores ;

  while ($line = <FILE_FREQ_ALL_TITLES>)
  {
    next if $line =~ /^#/ ;
    chomp $line ;
    ($word,$count) = split (',', $line) ;
    $words_total  += $count ;
    $words_unique ++ ;
  }
  close FILE_FREQ_ALL_TITLES ;

  print &Comma ($words_total) . " total words, and " . &Comma ($words_unique) . " unique words found in all pages combined\n\n" ;

  open FILE_FREQ_ALL_TITLES, "<", $file_freq_words_all_titles || abort ("Input file '" . $file_freq_words_all_titles . "' could not be opened.") ;
  binmode FILE_FREQ_ALL_TITLES ;
  while ($line = <FILE_FREQ_ALL_TITLES>)
  {
    next if $line =~ /^#/ ;
    chomp $line ;
    ($word,$count) = split (',', $line) ;
    $wordfreq = sprintf ("%.9f", $count / $words_total) ;
    $wordfreq_all_titles {$word} = $wordfreq ;

    if (++ $lines % 100000 == 0)
    { print "$word $wordfreq\n" ; }
  }
  close FILE_FREQ_ALL_TITLES ;

  open FILE_FREQ_PER_CATEGORY,        "<", $file_freq_words_per_category  || abort ("Input file '"  . $file_freq_words_per_category .  "' could not be opened.") ;
  open FILE_WORD_SCORES_PER_CATEGORY, ">", $file_word_scores_per_category || abort ("Output file '" . $file_word_scores_per_category . "' could not be opened.") ;

  my $tuples_qualified = $false ;
  while ($line = <FILE_FREQ_PER_CATEGORY>)
  {
    next if $line =~ /^#/ ;

    chomp $line ;
    ($category,$words_total,$wordlist_in) = split (',', $line) ;

    foreach $tuple (split '\|', $wordlist_in)
    {
      ($word,$count) = split (':', $tuple) ;
      next if $word eq '' ;
      # next if $count < 10 ;
      $tuples_qualified = $true ;
      $wordfreq = sprintf ("%.9f", $count / $words_total) ;
      $score = $wordfreq - $wordfreq_all_titles {$word} ;
      print sprintf ("%.0f",1000_000_000 * $score) . " $category $word [" . (1000_000_000 * $wordfreq) . "] [" . (1000_000_000 * $wordfreq_all_titles {$word}) . "]\n" ;
      $scores {$word} = $score ;
    # print "tuple $tuple, word $word, count $count\n" ;
    }

    my $lines = 0 ;
    foreach $word (sort {$scores {$a} <=> $scores {$b}} keys %scores)
    {
      last if ++$lines > 10 ;
      print "$category $word " . $scores {$word} . "\n" ;

      undef %scores ;
    }
  }
}

sub Comma
{
  my $num = shift ;
  $num =~ s/(\d+)(\d\d\d\d\d\d\d\d\d)$/$1,$2/ ;
  $num =~ s/(\d+)(\d\d\d\d\d\d)$/$1,$2/ ;
  $num =~ s/(\d+)(\d\d\d)$/$1,$2/ ;
  return ($num) ;
}


#stat1005:
#105,072 MB [  +858 titles]
#105,082 MB [  +596 titles]
#105,092 MB [ +1012 titles]
#105,102 MB [ +1094 titles]
#105,112 MB [  +916 titles] 21,141 sec, 68,011684 titles (3,217/sec)) -> 10,351889 unique words
#105,122 MB [  +184 titles]
#105,132 MB [  +990 titles]
#105,142 MB [  +672 titles]
#105,152 MB [  +774 titles]
#105,162 MB [  +598 titles] 21,150 sec, 68,053862 titles (3,218/sec)) -> 10,354272 unique words
#105,172 MB [ +1026 titles]
#105,182 MB [  +810 titles]
#105,192 MB [  +878 titles]
#105,202 MB [  +660 titles]

#-rw-r--r-- 1 ezachte wikidev  28M 2014-10-23 18:16 enwiki-20141008-pages-meta-current_freq_categories.txt
#-rw-r--r-- 1 ezachte wikidev 145M 2014-10-23 21:51 enwiki-20141008-pages-meta-current_freq_words_all_titles.txt
#-rw-r--r-- 1 ezachte wikidev 9.6G 2014-10-23 21:53 enwiki-20141008-pages-meta-current_freq_words_per_title.txt

