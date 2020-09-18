#!/data/wok/tools/perl-5.16.1/bin/perl
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

my @Months   = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my $time     = &GetLogTime();

print "$time - Starting\n";

my $agent    = LWP::UserAgent->new(agent => 'UNESP Search Agent');
my $auth_url     = 'http://search.webofknowledge.com/esti/wokmws/ws/WOKMWSAuthenticate';
my $search_url   = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearchLite';
my $retrieve_url = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearchLite';

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
                                Content      => $auth_request );

if( $response->is_success ){
   $auth_response = XMLin( $response->content );
   $auth_token   = $$auth_response{'soap:Body'}{'ns2:authenticateResponse'}{'return'};
   print "Token   : $auth_token\n";
} else {die( $! ) };

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
my $search_request = qq{ <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                          xmlns:woksearch="http://woksearchlite.v3.wokmws.thomsonreuters.com">
                            <soapenv:Header/>
                            <soapenv:Body>
                               <woksearch:search>
                                  <queryParameters>
                                     <databaseId>WOS</databaseId>
                                     <userQuery>AD=(Unesp OR Univ* Estad* Paulista OR S* Paulo State Univ* OR Paulista State Univ* OR State Univ* S* Paulo OR State Univ* Paulista OR Mesquita Filho OR IBILCE)</userQuery>
                                     <timeSpan>
                                        <begin>2012-01-01</begin>
                                        <end>2012-12-31</end>
                                     </timeSpan>
                                     <queryLanguage>en</queryLanguage>
                                  </queryParameters>
                                  <retrieveParameters>
                                     <firstRecord>$first_record</firstRecord>
                                     <count>100</count>
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
} else {die( $response->as_string ) };

#######################################################################
#Step 2: Process first envelope
#######################################################################

my $target_file = undef;

#The first envelope is processed outside the loop
open( $target_file , '>' , "/data/wok/wok_search/records/wos_unesp_$file_count.xml");
print $target_file $response->content();
close( $target_file );

$file_count++;
$first_record += 100;

$time     = &GetLogTime();
print "$time - Fetched first records\n";

#######################################################################
#Step 3: Retrieve remaining records
#######################################################################
my $iteration = 1;
while( $first_record < $record_count ){

$time     = &GetLogTime();
print "$time - Iteration $iteration\n";
my $retrieve_request = qq{ <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                              <soap:Body>
                                 <ns2:retrieve xmlns:ns2="http://woksearchlite.v3.wokmws.thomsonreuters.com">
                                    <queryId>$query_id</queryId>
                                    <retrieveParameters>
                                       <firstRecord>$first_record</firstRecord>
                                       <count>100</count>
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

   open( $target_file , '>' , "/data/wok/wok_search/records/wos_unesp_$file_count.xml");
   print $target_file $response->content();
   close( $target_file );

} else {die( $response->as_string ) };

$file_count++;
$first_record += 100;
$iteration++;

sleep(3); #Thou shalt not hammer the server

};
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

