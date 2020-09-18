#!/exlibris/product_br/perl-5.20.0/bin/perl

$| = 1;

use strict;
use warnings;
use Data::Dumper;
use HTTP::Request::Common; #POST request definition
use HTTP::Cookies;         #Cookies
use LWP::UserAgent;        #Agent
use XML::Simple;           #Parse results
use MIME::Base64 qw/ encode_base64 /;

chdir( "/exlibris/aleph/a22_1/alephm/wok_search" );

my @months   = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my $time     = &get_log_time();

my @id_list = ();
my $fail    = 0;
my $ok      = 0;

my $agent        = LWP::UserAgent->new(agent => 'UNESP Search Agent');
my $auth_url     = 'http://search.webofknowledge.com/esti/wokmws/ws/WOKMWSAuthenticate';
my $search_url   = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearchLite';
my $retrieve_url = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearchLite';

my $record_count = 0;
my $file_count   = '00001';

my $user_pass    = 'UNESP:';
   $user_pass    = "Basic ".&encode_base64( $user_pass );

#######################################################################
#Step 1: Load ID list
#######################################################################
print "Loading ID list...\n\n";
open( my $id_file , '<' , '/exlibris/aleph/a22_1/alephm/wok_search/ids_wos' );
open( my $id_file_fail , '>' , '/exlibris/aleph/a22_1/alephm/wok_search/ids_wos_fail');

while( my $line = <$id_file> ){
   chomp( $line );
   if( $line =~ /^WOS:.{15}$/ ){
     $ok++;
     push(@id_list , $line);
   }else{
     $fail++;
     print $id_file_fail "$line\n";
   };
};

close( $id_file );
close( $id_file_fail );

print "OK   : $ok\n";
print "Fail : $fail\n";

print "\n\n";

#######################################################################
#Step 2: Get the authentication token (session ID)
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
                                Content_Type  => 'text/xml',
                                Content       => $auth_request,
                                Authorization => $user_pass );


if( $response->is_success ){
   $auth_response = XMLin( $response->content );
   $auth_token   = $$auth_response{'soap:Body'}{'ns2:authenticateResponse'}{'return'};
   print "Token   : $auth_token\n";
} else {die( $response->content ) };

#$response = undef;

$time     = &get_log_time();
print "$time - Fetched session number\n";

my $search_count = 0;

while( $id_list[0] ){

   my $search_request = qq{<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:woksearch="http://woksearchlite.v3.wokmws.thomsonreuters.com">\n}.
                        qq{  <soapenv:Header/>\n}.
                        qq{    <soapenv:Body>\n}.
                        qq{      <woksearch:retrieveById>\n}.
                        qq{        <databaseId>WOS</databaseId>\n};
                       
      for( my $i = 0 ; $i < 100 ; $i++ ){
         if($id_list[0]){
            $search_request .= qq{        <uid>$id_list[0]</uid>\n};
            shift(@id_list);
         };
      };
     
      $search_request .= qq{        <queryLanguage>en</queryLanguage>\n};
      $search_request .= qq{        <retrieveParameters>\n};
      $search_request .= qq{          <firstRecord>1</firstRecord>\n};
      $search_request .= qq{          <count>100</count>\n};
      $search_request .= qq{        </retrieveParameters>\n};
      $search_request .= qq{     </woksearch:retrieveById>\n};
      $search_request .= qq{   </soapenv:Body>\n};
      $search_request .= qq{ </soapenv:Envelope>\n};
      
      $time = &get_log_time();
      $search_count++; 
      print "$time - Search $search_count\n";     

      my $search_response = undef;
      my $query_id        = undef;

      $response = undef;
 
      $response = $agent->request( POST $search_url,
                             Content_Type => 'text/xml',
                             Content      => $search_request );

      if( $response->is_success ){
          $search_response = XMLin( $response->content );
          $query_id     = $$search_response{'soap:Body'}{'ns2:retrieveByIdResponse'}{'return'}{'queryId'};
          $record_count = $$search_response{'soap:Body'}{'ns2:retrieveByIdResponse'}{'return'}{'recordsFound'};
          #print "ID      : $query_id\n";
	  $time = &get_log_time();
          print "$time - Records : $record_count\n";
      } else {die( $response->as_string ) };

      my $target_file = undef;

      $time = &get_log_time();
      #The first envelope is processed outside the loop
      open( $target_file , '>' , "/exlibris/aleph/a22_1/alephm/wok_search/records/wos_unesp_$file_count.xml");
      print $target_file $response->content();
      close( $target_file );

      print "$time - Created wos_unesp_$file_count.xml\n";

      $file_count++;

};                          

$time     = &get_log_time();
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

$time     = &get_log_time();
print "$time - Disconnected...\n\n";

exit(0);




#############################################################################
#Description: Get system current date/time formated as apache log
#
#Input      : 1 - Date/Time separator to be used
#
#Output     : 1 - String with date and time
#############################################################################
sub get_log_time
{

  my @now = localtime(time());
  my $day   = $now[3];
  #month : (0..11)
  my $month = $months[$now[4]];
  #year  : since 1900
  my $year   = $now[5]+1900;

  $day   = '0'.$day unless ($day>=10);
  #$Month = '0'.$Month unless ($Month>=10);

  $now[2]= '0'.$now[2] unless ($now[2]>=10);
  $now[1]= '0'.$now[1] unless ($now[1]>=10);
  $now[0]= '0'.$now[0] unless ($now[0]>=10);

  my $hour   = $now[2].":".$now[1].":".$now[0];
  return("[$day/$month/$year:$hour]");
};
#############################################################################

