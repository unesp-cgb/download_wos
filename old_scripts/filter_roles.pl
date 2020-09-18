#!/exlibris/product_br/perl-5.20.0/bin/perl

$| = 1;

use strict;
use warnings;
use XML::LibXML;
use File::Find;

my $wrong     = 0;
my %displayed = ();

open( my $out , '>' , 'corrigir_autores_wos.xml' );
find( \&wanted , '/exlibris/aleph/a22_1/alephm/wok_search/records_test' );
close( $out );
print "Wrong : $wrong\n\n";


sub wanted{
  my $file = $_;
  my $file_and_path = $File::Find::name;

  return unless( -f $file_and_path );
  return unless( $file_and_path =~ /\.xml$/ );

  my $parser = XML::LibXML->new();
  #print "Processing $file\n"; 
  #Here we parse the file and go direct to records using XPath
  my $records_step_1 = ($parser->parse_file($file_and_path)->findnodes('//records'))[0];
  #And this screws the XPath search...
  my $records_step_2 = $parser->load_xml( string => $records_step_1->textContent())->getDocumentElement();

  my $xc = XML::LibXML::XPathContext->new( $records_step_2 );
     $xc->registerNs('ns','http://scientific.thomsonreuters.com/schema/wok5.4/public/FullRecord');

  my @records =  $xc->findnodes('//ns:REC');

  foreach my $rec (@records){
    my $id = ($rec->getElementsByTagName('UID'))[0]->textContent();
    my $name_group =  ($rec->getElementsByTagName('names'))[0];
    my @names      = $name_group->getElementsByTagName('name');
    my $fix_it     = 0;

    foreach my $name ( @names ){
       my $role = $name->getAttribute('role');
       #print "No role\n" unless( $role );
       $fix_it = 1 unless($role);
       if( $role && $role ne 'author'){
          if( $displayed{$id} ){
	     print "                      found role $role -> ",($name->getElementsByTagName('display_name'))[0]->textContent,"\n";
          }else{
             print "$id : found role $role -> ",($name->getElementsByTagName('display_name'))[0]->textContent,"\n";
             $displayed{$id} = 1;
          } 
          
          $fix_it = 1;
       };
    };

   if( $fix_it ){
      print $out $rec->toString();
      $wrong++;
   };

  };
};


