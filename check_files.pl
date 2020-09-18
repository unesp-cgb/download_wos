#!/exlibris/product_br/perl-5.20.0/bin/perl

use strict;
use warnings;
use Data::Dumper;
use File::Find;
use XML::Simple;

find( \&wanted , '/exlibris/aleph/a22_1/alephm/wok_search/records' );

sub wanted{
  my $file = $_;
  my $file_and_path = $File::Find::name;

  if( -f $file_and_path ){
     $file =~ s/.xml//;
     my $ref = XMLin($file_and_path);
     #print $$ref{UID},"\n";
     print "Check $file_and_path\n" if($file ne $$ref{UID});
  };

};
