#!/exlibris/product_br/perl-5.20.0/bin/perl
#
#Creates the database files to store info about the 
#already retrieved records
#
use strict;
use warnings;
use DBI;

my %id_list = ();
my $dbfile  = 'wos_client_data.db';
my $dbh     = DBI->connect( "dbi:SQLite:dbname=$dbfile", undef, undef, {AutoCommit => 1});

$dbh->do( "drop table retrieved_records" );
$dbh->do( "drop table session" );
$dbh->do( "drop table queue" );

$dbh->do( "create table retrieved_records(wos_id text)" );
$dbh->do( qq{create table session(token     text, 
                                  date_from text, 
                                  date_to   text, 
                                  query     text,
                                  rec_count integer, 
                                  start_rec integer, 
                                  step      integer,
                                  active    text,
                                  start_session text,
                                  end_session   text,
                                  start_step1 text,
                                  end_step1   text,
                                  start_step2 text,
                                  end_step2   text)} );
$dbh->do( "create table queue(wos_id text)" );

my $sth1    = $dbh->prepare("insert into retrieved_records(wos_id) values(?)"); 
my $sth2    = $dbh->prepare("select count(1) from retrieved_records"); 
my $recnum = 0;

open( my $in , '<' , 'rec_list.txt' );
while( my $line = <$in> ) {
  chomp( $line );
  $line =~ s/^\s+//;
  $line =~ s/\s+$//;
  $line = uc($line);

  next unless( $line );
  $id_list{$line} = 1;
};
close($in);

foreach my $key (sort keys %id_list){
  $recnum++;
  print "Processing $recnum...\n" unless($recnum % 1000);
  $sth1->execute($key);
};
$sth1->finish;

$sth2->execute();
my @num = $sth2->fetchrow_array();
$sth2->finish;

print "Loaded $num[0]\n";


$dbh->disconnect;

exit(0);
