#!/exlibris/product_br/perl-5.20.0/bin/perl
######################################################
#Trying to rebuild the WoS data retriever 
#using a proper SOAP client 
######################################################
use strict;
use warnings;
use Data::Dumper;
use MIME::Base64 qw/ encode_base64 /;

use SOAP::Lite +trace => 'all'; ;

my $auth_url    = 'http://search.webofknowledge.com/esti/wokmws/ws/WOKMWSAuthenticate';
my $user        = 'UNESP';
my $pass        = '';

print "Before create\n";
my $soap_client = SOAP::Lite->uri($auth_url)
                            ->proxy($auth_url);

print "After create\n";

print "Header\n";
my $auth_header = SOAP::Header->name( Authorization => "Basic ".encode_base64("$user:$pass") );
print "Method\n";
my $auth_method = SOAP::Data->new(name => 'auth:authenticate', 
                                  type => 'nonil', 
                                  attr => {'xmlns:auth' => 'http://auth.cxf.wokmws.thomsonreuters.com'});
 

print "Before call\n";
my $response    = $soap_client->call($auth_method, $auth_header)->result;
print "After call\n";

print Dumper( $response );;

#
#Hack to remove the xsi:nil
#
sub SOAP::Serializer::as_nonil
{
    my ($self, $value, $name, $type, $attr) = @_;
    delete $attr->{'xsi:nil'};
    return [ $name, $attr, $value ];
}
