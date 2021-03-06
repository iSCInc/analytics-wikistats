package PageViews::BotDetector;
use strict;
use warnings;
use Net::Patricia;
use Regexp::Assemble;




=head1 NAME


PageViews::BotDetector -- Web Bot detection based on ip and ua

=cut


=head1 DESCRIPTION

=begin html
This module provides functionality for detecting bots. 

It uses a Net::Patricia object (<a href="http://en.wikipedia.org/wiki/Radix%5Ftree">Patricia tree</a>) to
do a fast lookup on a list of pre-defined ip ranges for bots.

This list of pre-defined ip ranges were taken from the <a href="https://github.com/wikimedia/analytics-wikistats">wikistats project</a>.
 

=end html


=head1 METHODS

=cut

sub new {
  my ($class) = @_;
  my $raw_obj = { };
  $raw_obj->{ip_pat}      = new Net::Patricia;
  $raw_obj->{ua_regex} = undef;
  my $obj     = bless $raw_obj,$class;
  return $obj;
};


=head2 match_ip($self,$ip)

Does a fast lookup(using the patricia tree) to decide if the ip is in the ranges that bots are in.

=cut

sub match_ip {
  my ($self,$ip) = @_;

  my $label = undef;
  eval {
    $label = $self->{ip_pat}->match_string($ip);
  };

  if( !$@ && defined($label) ) {
    return $label;
  } else {
    return undef;
  };
};


=head2 match_ua($self,$ip)

Does pattern matching on the user-agent with a given list of keywords that bots are known to have.

=cut

sub match_ua {
  my ($self,$ua) = @_;
  if($ua =~ $self->{ua_regex}) {
    return 1;
  } else {
    return 0;
  };
};


# we use Regexp::Assemble to bundle together
# multiple regexes from Wikistats code into a bigger
# efficient regex
sub load_useragent_regex {
  my ($self) = @_;

  my $ra = Regexp::Assemble->new;
  $ra->add("bot");
  $ra->add("spider");
  $ra->add("crawler");
  $ra->add("http");
  $ra->add("google");

  my $re_str = $ra->as_string();
  $self->{ua_regex} = qr/$re_str/i;
};


sub load_ip_ranges {
  my ($self) = @_;
  my $p = $self->{ip_pat};
  my $label_google = "Google";
  my $label_yahoo  = "Yahoo";
  #   if (($address_11 ge "064.233.160")     && ($address_11 le "064.233.191"))     { $address = "!google:IP064" ; }
  #elsif (($address_11 ge "066.249.064")     && ($address_11 le "066.249.095"))     { $address = "!google:IP066" ; }
  #elsif (($address_11 ge "066.102.000")     && ($address_11 le "066.102.015"))     { $address = "!google:IP066" ; }
  #elsif (($address_11 ge "072.014.192")     && ($address_11 le "072.014.255"))     { $address = "!google:IP072" ; }
  #elsif (($address_11 ge "074.125.000")     && ($address_11 le "074.125.255"))     { $address = "!google:IP074" ; }
  #elsif (($address_11 ge "209.085.128")     && ($address_11 le "209.085.255"))     { $address = "!google:IP209" ; }
  $p->add_string("64.233.$_.0/24", $label_google)  for  160..191;
  $p->add_string("66.249.$_.0/24", $label_google)  for    64..95;
  $p->add_string("66.102.$_.0/24", $label_google)  for     0..15;
  $p->add_string( "72.14.$_.0/24", $label_google)  for  192..255;
  $p->add_string( "74.125.0.0/16", $label_google)              ;
  $p->add_string("209.85.$_.0/24", $label_google)  for  128..255;

  #elsif (($address_11 ge "216.239.032")     && ($address_11 le "216.239.063"))     { $address = "!google:IP216" ; }
  #elsif (($address    ge "070.089.039.152") && ($address    le "070.089.039.159")) { $address = "!google:IP070" ; }
  #elsif (($address    ge "070.090.219.072") && ($address    le "070.090.219.079")) { $address = "!google:IP070" ; }
  #elsif (($address    ge "070.090.219.048") && ($address    le "070.090.219.055")) { $address = "!google:IP070" ; }
  $p->add_string(  "216.239.$_.0/24",$label_google)  for  32..63;
  $p->add_string( "70.89.39.$_"     ,$label_google)  for  152..159;
  $p->add_string("70.90.219.$_"     ,$label_google)  for  72..79;
  $p->add_string("70.90.219.$_"     ,$label_google)  for  48..55;
 
  #elsif (($address_11 ge "067.195.000")     && ($address_11 le "067.195.255"))     { $address = "!yahoo:IP067" ;  }
  #elsif (($address_11 ge "072.030.000")     && ($address_11 le "072.030.255"))     { $address = "!yahoo:IP072" ;  }
  #elsif (($address_11 ge "074.006.000")     && ($address_11 le "074.006.255"))     { $address = "!yahoo:IP074" ;  }
  #elsif (($address_11 ge "209.191.064")     && ($address_11 le "209.191.127"))     { $address = "!yahoo:IP209" ;  }

  $p->add_string("67.195.0.0/16",$label_yahoo);
  $p->add_string("72.30.0.0/16",$label_yahoo);
  $p->add_string("74.6.0.0/16",$label_yahoo);
  $p->add_string("209.191.$_.0/24",$label_yahoo) for 64..127;

};


1;
