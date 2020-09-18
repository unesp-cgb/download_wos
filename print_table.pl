#!/exlibris/product_br/perl-5.20.0/bin/perl
###################################################################
#Author  : Oberdan Luiz May
#
#Version : 0.4 
#
#Changes : Rewrite of the original client, now supporting resume
#          and storing previously retrived record IDs
###################################################################

use strict;
use warnings;
use POSIX qw/ strftime /;
use DBI;

my $dbfile  = 'wos_client_data.db';
my $dbh     = DBI->connect( "dbi:SQLite:dbname=$dbfile", undef, undef, {AutoCommit => 1});
my $sth     = $dbh->prepare("select * from $ARGV[0]");

&print_table($sth);

#####################################################################
#####################################################################
sub print_table{

    my $sth  = shift;
    my $count = 0;

    $sth->execute;

    while( my $rec = $sth->fetchrow_hashref ){
       print "------------------\n";
       foreach my $key (keys %$rec){
          print "$key : $$rec{$key}\n" if($key && $$rec{$key});
       };
       $count++;
    };
    print "\nRecords: $count\n\n";
};
#####################################################################

