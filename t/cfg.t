#!/usr/bin/env perl
use strict;
use warnings;


use Test::More;
use Text::Diff;

BEGIN { 

  require App::RaffiWare::ExCollect::Worker;

}; 

use_ok('App::RaffiWare::Cfg');

my $cfg_file = "t/test.cfg";

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

close $cfg_fh;

$long_str =<<'END';;
some big long
string of multi
line test here


END

$cfg->set( long_text => $long_str );

$expected_cfg =<<'END';
---
long_text: |+
  some big long
  string of multi
  line test here
  

short_text: hi planet
END

open $cfg_fh, '<', $cfg_file or die $!;

$diffs = diff(\$expected_cfg, $cfg_fh);

close $cfg_fh;

ok !$diffs, 'expected config file';

diag explain $diffs;

$cfg_file = $cfg_file .'.json' ;
$cfg = App::RaffiWare::Cfg->new( cfg_storage => 'json', cfg_file =>  $cfg_file );

$cfg->set( short_text => 'in_json' );
$cfg->set( multiline_text => $long_str );

open $cfg_fh, '<', $cfg_file or die $!;

diag do { local $/; <$cfg_fh> };

close $cfg_fh; 

$cfg = App::RaffiWare::Cfg->new( cfg_storage => 'json', cfg_file =>  $cfg_file ); 

is $cfg->get('multiline_text'), $long_str, 'got multiline string back';

done_testing(); 
