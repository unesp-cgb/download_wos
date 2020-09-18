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
use Cwd;
use POSIX qw/ strftime /;
use DBI;
use Data::Dumper;
use HTTP::Request::Common; #POST request definition
use HTTP::Cookies;         #Cookies
use LWP::UserAgent;        #Agent
use XML::LibXML;           #Parse using libxml
use MIME::Base64 qw/ encode_base64 /;

$| = 1;

my $agent       = LWP::UserAgent->new(agent => 'UNESP Search Agent');
my $dbfile      = 'wos_client_data.db';
my $dbh         = DBI->connect( "dbi:SQLite:dbname=$dbfile", undef, undef, {AutoCommit => 1});

my $list_ids    = $dbh->prepare(qq{select wos_id from retrieved_records});
my $add_id      = $dbh->prepare(qq{insert into retrieved_records(wos_id) values(?)});

my $add_queue   = $dbh->prepare(qq{insert into queue(wos_id) values(?)});
my $del_queue   = $dbh->prepare(qq{delete from queue where wos_id = ?});
my $list_queue  = $dbh->prepare(qq{select wos_id from queue});
my $count_queue = $dbh->prepare(qq{select count(1) from queue});

my $create_session   = $dbh->prepare(qq{insert into session(token, start_session, date_from, date_to, query, active) values(?,?,?,?,?,'Y')});
my $get_session      = $dbh->prepare(qq{select * from session});

my $auth_url     = 'http://search.webofknowledge.com/esti/wokmws/ws/WOKMWSAuthenticate';
my $search_url   = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearch';
my $retrieve_url = 'http://search.webofknowledge.com/esti/wokmws/ws/WokSearch';

my %stored_ids = ();
my %queue_ids  = ();

my $user_pass  = 'UNESP:';
my $token      = '';
my $date_from  = "2019-01-01";
my $date_to    = "2019-12-31";
my $query      = "AD=(Unesp OR Univ* Estad* Paulista OR S* Paulo State Univ* OR Paulista State Univ* OR State Univ* S* Paulo OR State Univ* Paulista OR Mesquita Filho OR IBILCE)";
my $query_id   = undef;

my $rec_count  = 0;
my $first_rec  = 1;
my $step       = 5;

chdir("/exlibris/aleph/a22_1/alephm/wok_search"); #Need this running on cron

#1 - Load already retrieved IDs from retrieved_records
print "Loading retrieved IDs...\n";
&load_ids(\%stored_ids , $list_ids);
print "Stored : ".scalar(keys %stored_ids),".\n\n";

#Authenticate on WoS
$token = &authenticate($agent,$auth_url,$user_pass);
print "Token : $token\n";

if( $token ){
   #Create session on DB
   $create_session->execute($token,&get_time,$date_from,$date_to,$query);

   if( &queue_size($count_queue) == 0 ){ #Are there queued records?
     #No? Run search
     ($query_id , $rec_count) = &search($agent,$search_url,$date_from,$date_to,$query,$first_rec,$step,\%stored_ids,$add_queue);
     print "Count : $rec_count.\n";
     $first_rec += $step;
     #Retrieve IDs
     while( $first_rec <= $rec_count ){
        &retrieve_ids($agent,$search_url,$query_id,$first_rec,$step,\%stored_ids,$add_queue);
        $first_rec += $step;
        sleep(2);
     };

   }else{ print "Found ",&queue_size($count_queue)," remaining records. Resuming...\n\n" };

   print "Loading queued IDs...\n";
   &load_ids(\%queue_ids,$list_queue);
   print "Queued : ".scalar(keys %queue_ids),".\n\n";

   foreach my $id (keys %queue_ids){
      if(&retrieve_record($agent,$retrieve_url,$id)){
        print "Deleting $id from queue...\n";
        $del_queue->execute($id);
        print "Adding $id to history...\n";
        $add_id->execute($id);
        #sleep(1);
      };
   };

};

%stored_ids = ();

#1 - Load already retrieved IDs
print "Loading retrieved IDs...\n";
&load_ids(\%stored_ids , $list_ids);
print "Stored : ".scalar(keys %stored_ids),".\n\n";

&dump_rec_list(\%stored_ids,'test.txt');


#####################################################################
#Load previously stored IDs
#####################################################################
sub load_ids{
   my $list = shift;
   my $sta  = shift;

   $sta->execute();

   while( my @rec = $sta->fetchrow_array ){
     $$list{$rec[0]} = 1;
   };
};
#####################################################################

#####################################################################
#Authenticate on WoS and update and create the session record.
#####################################################################
sub authenticate{
   my $ag      = shift;
   my $url     = shift;
   my $pass    = shift;

   my $resp    = undef;
   my $tok     = undef;
   my $parser  = XML::LibXML->new;

   my $auth_request = qq{<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                          xmlns:auth="http://auth.cxf.wokmws.thomsonreuters.com">
                           <soapenv:Header/>
                           <soapenv:Body>
                              <auth:authenticate/>
                           </soapenv:Body>
                        </soapenv:Envelope>};

   $pass = "Basic ".&encode_base64( $pass );

   $ag->cookie_jar({});

   $resp = $ag->request( POST $url,
                         Content_Typei  => 'text/xml',
                         Content       => $auth_request,
                         Authorization => $pass );

   if( $resp->is_success ){
      my $doc = $parser->parse_string($resp->content);
         $tok = ($doc->getElementsByTagName('return'))[0];
         $tok = $tok->textContent if($tok);
   }else{ 
      my $error = $resp->status_line;
      print "$error\n";
      exit(1) if ($error =~ /^500/);
   };
   return($tok);
};
#####################################################################

#####################################################################
#Run the first search and retrieve the first records
#####################################################################
sub search{

   my $ag    = shift;
   my $url   = shift;
   my $start = shift;
   my $end   = shift;
   my $query = shift;
   my $first = shift;
   my $step  = shift;
   my $ids   = shift;
   my $queue = shift; 

   my $resp  = undef;
   my $qid   = 0;
   my $count = 0;
   my @uids  = ();
   my $parser = XML::LibXML->new;

   my $search_request = qq{ <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                             xmlns:woksearch="http://woksearch.v3.wokmws.thomsonreuters.com">
                               <soapenv:Header/>
                               <soapenv:Body>
                                  <woksearch:search>
                                     <queryParameters>
                                        <databaseId>WOS</databaseId>
                                        <userQuery>$query</userQuery>
                                        <timeSpan>
                                           <begin>$start</begin>
                                           <end>$end</end>
                                        </timeSpan>
                                        <queryLanguage>en</queryLanguage>
                                     </queryParameters>
                                     <retrieveParameters>
                                        <firstRecord>$first</firstRecord>
                                        <count>$step</count>
                                        <viewField>
                                          <collectionName>WOS</collectionName>
                                          <fieldName>UID</fieldName>
                                        </viewField>
                                     </retrieveParameters>
                                  </woksearch:search>
                               </soapenv:Body>
                            </soapenv:Envelope>};

   $resp = $ag->request( POST $url,
                         Content_Type => 'text/xml',
                         Content      => $search_request );

   print "Step  1 $first - $step\n";
   if( $resp->is_success ){
      my $doc   = $parser->parse_string( $resp->content );
         $qid   = ($doc->getElementsByTagName('queryId'))[0]->textContent;
         $count = ($doc->getElementsByTagName('recordsFound'))[0]->textContent;

      my $recs  = $parser->load_xml( string => ($doc->getElementsByTagName('records'))[0]->textContent );
      my @uids  = $recs->getElementsByTagName('UID');

      foreach my $id ( @uids ){
          $id = $id->textContent;
          if($$ids{$id}){
             print "$id already found.\n";
          }else{ 
             print "$id added to queue.\n";
             $queue->execute($id);
          };
      };

   }else{
      my $error = $resp->status_line;
      print "$error\n";
      exit(1) if ($error =~ /^500/);
   };

  return( $qid , $count ); 
};
#####################################################################

#####################################################################
#Retrieve the remaining IDs 
#####################################################################
sub retrieve_ids{

   my $ag       = shift;
   my $url      = shift;
   my $query_id = shift;
   my $first    = shift;
   my $step     = shift;

   my $ids      = shift;
   my $queue    = shift;

   my $resp  = undef;
   my $qid   = 0;
   my $count = 0;
   my @uids  = ();
   my $parser = XML::LibXML->new;

   my $retrieve_request = qq{<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                                <soap:Body>
                                   <ns2:retrieve xmlns:ns2="http://woksearch.v3.wokmws.thomsonreuters.com">
                                      <queryId>$query_id</queryId>
                                      <retrieveParameters>
                                         <firstRecord>$first</firstRecord>
                                         <count>$step</count>
                                      </retrieveParameters>
                                   </ns2:retrieve>
                               </soap:Body>
                             </soap:Envelope>};


   $resp = $ag->request( POST $url,
                         Content_Type => 'text/xml',
                         Content      => $retrieve_request );
   print "Step $first - $step\n";
   if( $resp->is_success ){
      my $doc   = $parser->parse_string( $resp->content );
      my $recs  = $parser->load_xml( string => ($doc->getElementsByTagName('records'))[0]->textContent );
      my @uids  = $recs->getElementsByTagName('UID');

      foreach my $id ( @uids ){
          $id = $id->textContent;
          if($$ids{$id}){
             print "$id already found.\n";
          }else{
             print "$id added to queue.\n";
             $queue->execute($id);
          };
      };
   }else{
      my $error = $resp->status_line;
      print "$error\n";
      exit(1) if ($error =~ /^500/);
   };
};
#####################################################################

#####################################################################
#Retrieve the full record
#####################################################################
sub retrieve_record{
   my $ag       = shift;
   my $url      = shift;
   my $wos_id   = shift;

   my $resp     = undef;
   my $here     = &cwd();
   my $result   = 0;
   my $parser   = XML::LibXML->new();

   my $retrieve_request = qq{<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                              xmlns:woksearch="http://woksearch.v3.wokmws.thomsonreuters.com">
                               <soapenv:Header/>
                               <soapenv:Body>
                                  <woksearch:retrieveById>
                                  <databaseId>WOS</databaseId>
                                  <uid>$wos_id</uid>
                                  <queryLanguage>en</queryLanguage>
                                     <retrieveParameters>
                                        <firstRecord>1</firstRecord>
                                        <count>1</count>
                                     </retrieveParameters>
                                  </woksearch:retrieveById>
                               </soapenv:Body>
                            </soapenv:Envelope>};

   if( -f "$here/records/$wos_id.xml" ){
     print "ID $wos_id already retrieved\n";
     $result = 1;
   }else{

      print "Retrieving $wos_id...\n";

      $resp = $ag->request( POST $url,
                            Content_Type => 'text/xml',
                            Content      => $retrieve_request );

      if( $resp->is_success ){
      
         my $step1  = $parser->load_xml( string => $resp->content , { no_blanks => 1 } );
         my $step2  = $parser->load_xml( string => ($step1->getElementsByTagName('records'))[0]->textContent, { no_blanks => 1 } );
         my $step3  = ($step2->getElementsByTagName('REC'))[0];

         my $found  = ($step1->getElementsByTagName('recordsFound'))[0]->textContent;
         print "Found : $found\n";
         if( $found ne '0' ){

            open(my  $target_file , '>' , "$here/records/$wos_id.xml");
            print $target_file $step3->toString(1);
            close( $target_file );

         }else{ print "ID $wos_id, for some weid reason, not found\n"; };

         $result = 1;
      }else{ 
         my $error = $resp->status_line;
         print "$error\n";
         exit(1) if ($error =~ /^500/);
      };
      sleep(1);
   };
   return($result);
};
#####################################################################

sub queue_size{
   my $sta = shift;

   $sta->execute;
   my @result = $sta->fetchrow_array;
   
   return($result[0]);
};

#####################################################################
#####################################################################
sub print_table{
    my $sth  = shift;

    $sth->execute;

    while( my $rec = $sth->fetchrow_hashref ){
       print "------------------\n";
       foreach my $key (keys %$rec){
          print "$key : $$rec{$key}\n" if($key && $$rec{$key});
       };
    };
};
#####################################################################

sub dump_rec_list{
   my $recs = shift;
   my $file = shift;

   open(my $out, '>', $file);

   foreach my $id (sort keys %$recs){
     print $out "$id\n";
   };

   close($out);
};

#####################################################################
#####################################################################
sub get_time{
   return( strftime('%Y-%m-%d %H:%M:%S',localtime())) ;
};
#####################################################################
