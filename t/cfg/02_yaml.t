#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { require App::RaffiWare::ExCollect::Worker; }; 

use Test::Most;
use Text::Diff;

use App::RaffiWare::Cfg;

my $cfg_file = "t/cfg/test.yaml";
my $bad_cfg_file = "t/cfg/test_bad.yaml";

unlink $cfg_file;

my $cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file );

$cfg->set( short_text => 'hi planet' ); 

my $long_str =<<'END';
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

$cfg->delete('short_text');

$expected_cfg =<<'END';
---
long_text: |+
  some big long
  string of multi
  line test here
  

END

open $cfg_fh, '<', $cfg_file or die $!;

$diffs = diff(\$expected_cfg, $cfg_fh);

close $cfg_fh;

ok !$diffs, 'key deleted';

is ref($cfg->data), 'HASH', 'data';  

throws_ok { App::RaffiWare::Cfg->new( cfg_file =>  $bad_cfg_file );}
          qr|^Config file t/cfg/test_bad.yaml failed to load with error: YAML Error:|,
          'expected error on badly formatted config';


done_testing();
