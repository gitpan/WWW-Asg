use strict;
use warnings;
use utf8;

use Test::More;
use WWW::Asg;
use Encode;

open( IN, "t/fixture/contentsPage.html" );
my $html = Encode::decode( 'utf8', join '', <IN> );
close IN;

my $expect_pt = '503ef17e0f5e78bddbb708deafd35af63848c900';

my $asg           = WWW::Asg->new;
my $pt = $asg->_pt($html);

is $pt, $expect_pt;

done_testing();
