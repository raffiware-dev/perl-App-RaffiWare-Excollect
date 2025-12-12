#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { require App::RaffiWare::ExCollect::Worker; };  

use Test::More;
use Text::Diff;

use App::RaffiWare::Cfg;

my $cfg_file = "t/cfg/test.json";
my $short_str = 'in json';
my $long_str =<<'END';;
some big long
string of multi
line test here


END

unlink $cfg_file;
my $cfg = App::RaffiWare::Cfg->new( cfg_storage => 'json', cfg_file =>  $cfg_file );

$cfg->set( short_text => $short_str );
$cfg->set( multiline_text => $long_str );

open my $cfg_fh, '<', $cfg_file or die $!;

close $cfg_fh; 

$cfg = App::RaffiWare::Cfg->new( cfg_storage => 'json', cfg_file =>  $cfg_file ); 

is $cfg->get('short_text'),     $short_str, 'got multiline string back'; 
is $cfg->get('multiline_text'), $long_str,  'got multiline string back';

$cfg->delete('short_text'); 

$cfg = App::RaffiWare::Cfg->new( cfg_storage => 'json', cfg_file =>  $cfg_file );

ok !defined  $cfg->json->config->{short_text}, 'key deleted';

is  ref($cfg->data), 'HASH', 'data';

done_testing();
