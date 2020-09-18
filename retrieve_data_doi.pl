#!/exlibris/product_br/perl-5.20.0/bin/perl
#######################################################################
#Description: Retrieves data from Web of Knowledge using their SOAP
#             interface instead of scrapping the HTML. It does not use 
#             a default SOAP client because of:
#             
#Author     : Oberdan Luiz May
#
#Date       : 09-20-2012
#######################################################################
$| = 1;

use strict;
use warnings;
use Data::Dumper;
use HTTP::Request::Common; #POST request definition
use HTTP::Cookies;         #Cookies
use LWP::UserAgent;        #Agent
use XML::Simple;           #Parse results
use MIME::Base64 qw/ encode_base64 /;

my @Months   = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my $time     = &GetLogTime();

print "$time - Starting\n";

my $agent    = LWP::UserAgent->new(agent => 'UNESP Search Agent');
my $auth_url     = 'http://search.webofknowledge.com/esti/wokmws/ws/WOKMWSAuthenticate';
my $search_url   = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearch';
my $retrieve_url = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearch';

my $user_pass    = 'UNESP:';
#my $user_pass    = 'Unesp_HG:70JKVVOQ';
   $user_pass    = "Basic ".&encode_base64( $user_pass );

#######################################################################
#Step 1: Get the authentication token (session ID)
#######################################################################
my $auth_request = qq{<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                       xmlns:auth="http://auth.cxf.wokmws.thomsonreuters.com">
                        <soapenv:Header/>
                        <soapenv:Body>
                           <auth:authenticate/>
                        </soapenv:Body>
                     </soapenv:Envelope>};

my $auth_response = undef;
my $auth_token    = undef;

#Set an empty cookie jar for the agent (the cookie is needed to close the session)
$agent->cookie_jar({});
#Post the envelope to the server and get the response.
my $response = $agent->request( POST $auth_url, 
                                Content_Type => 'text/xml', 
                                Content      => $auth_request,
                                Authorization => $user_pass );


if( $response->is_success ){
   $auth_response = XMLin( $response->content );
   $auth_token   = $$auth_response{'soap:Body'}{'ns2:authenticateResponse'}{'return'};
   print "Token   : $auth_token\n";
} else {die( $response->content ) };

$response = undef;

$time     = &GetLogTime();
print "$time - Fetched session number\n";

my $first_record = 1;
my $record_count = 0;
my $file_count   = '00001';

#######################################################################
#Step 2: First search
#######################################################################
#<userQuery>AD=(unesp OR Univ* Estad* Paulista OR S* Paulo State Univ* OR Paulista State Univ*)</userQuery>

open( my $in   , '<' , 'doi_list.csv' );
open( my $out   , '>' , 'doi_keywords.csv' );

while( my $doi = <$in> ){
chomp( $doi );
$doi = &trim( $doi );
print "Lenght : ",length( $doi ),"\n";

if( length($doi) < 5 ){
   print $out "$doi\n";
   $doi = "" unless( $doi );

   print "Skipping $doi\n";
   next;
};

$doi = "\"".$doi."\"";


print "Processing $doi...\n";

my $search_request = qq{ <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                          xmlns:woksearch="http://woksearch.v3.wokmws.thomsonreuters.com">
                            <soapenv:Header/>
                            <soapenv:Body>
                               <woksearch:search>
                                  <queryParameters>
                                     <databaseId>WOS</databaseId>
                                     <userQuery>DO=$doi</userQuery>
                                     <queryLanguage>en</queryLanguage>
                                  </queryParameters>
                                  <retrieveParameters>
                                     <firstRecord>$first_record</firstRecord>
                                     <count>1</count>
                                  </retrieveParameters>
                               </woksearch:search>
                            </soapenv:Body>
                         </soapenv:Envelope>};

my $search_response = undef;
my $record          = undef
my $query_id        = undef;

$response = $agent->request( POST $search_url,
                             Content_Type => 'text/xml',
                             Content      => $search_request );

if( $response->is_success ){
   $search_response = XMLin( $response->content );
   $query_id     = $$search_response{'soap:Body'}{'ns2:searchResponse'}{'return'}{'queryId'};
   $record_count = $$search_response{'soap:Body'}{'ns2:searchResponse'}{'return'}{'recordsFound'};
   print "ID      : $query_id\n";
   print "Records : $record_count\n";
} else {die( $response->as_string ) };

#######################################################################
#Step 2: Process first envelope
#######################################################################

my $target_file = undef;

#The first envelope is processed outside the loop
my $content = $response->content();

    $content =~ s/&lt;/</mg;
    $content =~ s/&gt;/>/mg;
    $content =~ s/&amp;amp;/&amp;/mg;
    $content =~ s/&amp;apos;/&apos;/mg;

open( $target_file , '>' , "/exlibris/aleph/a22_1/alephm/wok_search/records/wos_unesp_$file_count.xml");
print $target_file $content;
close( $target_file );

$record = XMLin( $content );
$record = $$record{'soap:Body'}{'ns2:searchResponse'}{'return'}{'records'}{'records'}{'REC'}{'static_data'}{'fullrecord_metadata'}{'keywords'}{'keyword'};

#print Dumper( $$record{'soap:Body'}{'ns2:searchResponse'}{'return'}{'records'}{'records'}{'REC'}{'static_data'} );
#print Dumper( $$record{'soap:Body'}{'ns2:searchResponse'}{'return'}{'records'}{'records'}{'REC'} );

if( defined $record ){
   my $keywords = "";

   $doi =~ s/"//g;

   if( (ref $record) eq 'ARRAY'){
     $keywords = join('|',@$record);
   }elsif( (ref $record) eq 'SCALAR' ){
     $keywords = $record;
   };
   print $out "$doi\t$keywords\n";
}else{
   $doi =~ s/"//g;
   print $out "$doi\t \n";
};

sleep(2);
$file_count++;

};

$time     = &GetLogTime();
print "$time - Fetched first records\n";

#######################################################################
#Step 3: Retrieve remaining records
#######################################################################
my $iteration = 1;

$time     = &GetLogTime();
print "$time - End retrieving records...\n\n";
#######################################################################
#Step 4: Close session
#######################################################################
my $close_request = qq{<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                          <soap:Body>
                             <WOKMWSAuthentcate:closeSession 
                              xmlns:WOKMWSAuthentcate="http://auth.cxf.wokmws.thomsonreuters.com"/>
                          </soap:Body>
                       </soap:Envelope>};

$response = $agent->request( POST $auth_url,
                             Content_Type => 'text/xml',
                             Content      => $close_request );

$time     = &GetLogTime();
print "$time - Disconnected...\n\n";

exit(0);

#############################################################################
#Description: Get system current date/time formated as apache log
#
#Input      : 1 - Date/Time separator to be used
#
#Output     : 1 - String with date and time
#############################################################################
sub GetLogTime
{

  my @CurrentTime = localtime(time());
  my $Day   = $CurrentTime[3];
  #month : (0..11)
  my $Month = $Months[$CurrentTime[4]];
  #year  : since 1900
  my $Year   = $CurrentTime[5]+1900;

  $Day   = '0'.$Day unless ($Day>=10);
  #$Month = '0'.$Month unless ($Month>=10);

  $CurrentTime[2]= '0'.$CurrentTime[2] unless ($CurrentTime[2]>=10);
  $CurrentTime[1]= '0'.$CurrentTime[1] unless ($CurrentTime[1]>=10);
  $CurrentTime[0]= '0'.$CurrentTime[0] unless ($CurrentTime[0]>=10);

  my $Hour   = $CurrentTime[2].":".$CurrentTime[1].":".$CurrentTime[0];
  return("[$Day/$Month/$Year:$Hour]");
};
#############################################################################


sub trim{
   my $str = shift;
   return( "" ) unless defined( $str );

   $str =~ s/^\s+//;
   $str =~ s/\s+$//;

   return( $str );
};
