#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../lib";  

use Test::More;
use Text::Diff;

BEGIN { 

  my $fatbin = "$FindBin::Bin/../bin/exc"; 
  require $fatbin if -f $fatbin;

}; 

use_ok('App::RaffiWare::Cfg');

my $cfg_file = "$FindBin::Bin/test.cfg";

unlink $cfg_file;

my $cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file );  

$cfg->set( short_text => 'hi planet' ); 

my $long_str =<<'END';;
some big long
string of multi
line test here
END

$cfg->set( long_text => $long_str );

my $expected_cfg =<<'END';
---
long_text: |
  some big long
  string of multi
  line test here
short_text: hi planet
END

open my $cfg_fh, '<', $cfg_file or die $!;

my $diffs = diff(\$expected_cfg, $cfg_fh);

ok !$diffs, 'expected config file';

diag explain $diffs;

$cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file );   

is $cfg->get('long_text'), $long_str, 'got config value';

done_testing(); 
