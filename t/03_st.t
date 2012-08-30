use strict;
use warnings;
use utf8;

use Test::More;
use WWW::Asg;
use Encode;

my $mcd = 't8DWA8Lx9tn7M5vf';
my $pt = '503ef17e0f5e78bddbb708deafd35af63848c900';
my $expect_st = '759265d81f36105e4e8a1d41552133cd';

my $asg           = WWW::Asg->new;
my $st = $asg->_st($mcd, $pt);

is $st, $expect_st;

done_testing();
