#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Text::Diff;

use App::RaffiWare::Cfg;

$App::RaffiWare::Cfg::CFG_DEFAUTLS{'test_setting'} = 'some value';
$App::RaffiWare::Cfg::CFG_DEFAUTLS{'overriden'}    = 160;

my $cfg_file = "t/cfg/test.yaml";
unlink $cfg_file; 

my $cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file ); 

is $cfg->get('test_setting'), 'some value', 'default value';

is $cfg->get('overriden'), 160, 'number set value';  

$cfg->set( overriden => 0 );

is $cfg->get('overriden'), 0, 'zero set value'; 

done_testing();
 
