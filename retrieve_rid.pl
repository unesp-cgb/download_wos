#!/exlibris/product_br/perl-5.20.0/bin/perl
#######################################################################
#Description: Retrieves data from Web of Knowledge using their SOAP
#             interface instead of scrapping the HTML. It does not use 
#             a default SOAP client because of:
#             
#             - SOAP::Lite has the xsi:nil="true" "feature" that the 
#               server does not understand.
#
#             - SOAP::WSDL does not build correctly on perl 5.16.1.
#
#             - This is not so complicated and I've lost a lot of time 
#               trying to make the previous ones to work with no success. 
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
use XML::LibXML;           #Parse using libxml
use MIME::Base64 qw/ encode_base64 /;

my @Months   = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my $time     = &GetLogTime();

my %rec_ids  = ();

my $query      = "AI=(I-3117-2012)";
my $start_date = "2000-01-01"; 
my $end_date   = "2018-12-01"; 

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
my $step         = 1;
my $record_count = 0;

open(my $id_file , '>' , 'collected_ids.txt' );

#######################################################################
#Step 2: First search
#######################################################################
my $search_request = qq{ <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                          xmlns:woksearch="http://woksearch.v3.wokmws.thomsonreuters.com">
                            <soapenv:Header/>
                            <soapenv:Body>
                               <woksearch:search>
                                  <queryParameters>
                                     <databaseId>WOS</databaseId>
                                     <userQuery>$query</userQuery>
                                     <timeSpan>
                                        <begin>$start_date</begin>
                                        <end>$end_date</end>
                                     </timeSpan>
                                     <queryLanguage>en</queryLanguage>
                                  </queryParameters>
                                  <retrieveParameters>
                                     <firstRecord>$first_record</firstRecord>
                                     <count>$step</count>
                                     <viewField>
                                       <collectionName>WOS</collectionName>
                                       <fieldName>UID</fieldName>
                                       <fieldName>titles</fieldName>
                                     </viewField>
                                  </retrieveParameters>
                               </woksearch:search>
                            </soapenv:Body>
                         </soapenv:Envelope>};

my $search_response = undef;
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
   print $response->content;
} else {die( $response->as_string ) };

#######################################################################
#Step 2: Process first envelope
#######################################################################

my $target_file = undef;

#The first envelope is processed outside the loop
my $content = $response->content() ;
my $parser = XML::LibXML->new();
my $step1  = $parser->load_xml( string => $content , { no_blanks => 1 } );
my $step2  = $parser->load_xml( string => ($step1->getElementsByTagName('records'))[0]->textContent, { no_blanks => 1 } );
my @IDs    =  $step2->getElementsByTagName('UID'); 
 
foreach my $elem ( @IDs ){
   print $id_file $elem->textContent,"\n";
};

$first_record += $step;

$time     = &GetLogTime();
print "$time - Fetched first record\n";

#######################################################################
#Step 3: Retrieve remaining records
#######################################################################
while( $first_record <= $record_count ){

$time     = &GetLogTime();
print "$time - Record $first_record\n";
my $retrieve_request = qq{ <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                              <soap:Body>
                                 <ns2:retrieve xmlns:ns2="http://woksearch.v3.wokmws.thomsonreuters.com">
                                    <queryId>$query_id</queryId>
                                    <retrieveParameters>
                                       <firstRecord>$first_record</firstRecord>
                                       <count>$step</count>
                                    </retrieveParameters>
                                 </ns2:retrieve>
                             </soap:Body>
                           </soap:Envelope>};
                         
my $retrieve_response = undef;

$response    = undef;
$target_file = undef;

$response = $agent->request( POST $retrieve_url,
                             Content_Type => 'text/xml',
                             Content      => $retrieve_request );

if( $response->is_success ){
   
   my $content = $response->content() ;
   my $parser = XML::LibXML->new();
   my $step1  = $parser->load_xml( string => $content , { no_blanks => 1 } );
   my $step2  = $parser->load_xml( string => ($step1->getElementsByTagName('records'))[0]->textContent, { no_blanks => 1 } );

   my @IDs    =  $step2->getElementsByTagName('UID');

   foreach my $elem ( @IDs ){
      print $id_file $elem->textContent,"\n";
   };

} else {die( $response->as_string ) };

$first_record += $step;

sleep(2); #Thou shalt not hammer the server

};

$time     = &GetLogTime();

close( $id_file );

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
