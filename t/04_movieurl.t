use strict;
use warnings;
use utf8;

use Test::More;
use WWW::Asg;
use Encode;

open( IN, "t/fixture/contentsPage.xml" );
my $xml = Encode::decode( 'utf8', join '', <IN> );
close IN;

my $expect_movieurl= 'http://smedia16.asg.to/dm/4b94cb1a35a814945a47a3ff05c48e84/503ef3af/20120830/1346292951_296631_335575.flv';

my $asg           = WWW::Asg->new;
my $movieurl = $asg->_movieurl($xml);

is $movieurl, $expect_movieurl;

done_testing();
