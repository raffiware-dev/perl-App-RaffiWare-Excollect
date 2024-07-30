#!/usr/bin/env perl
use strict;
use warnings;


BEGIN { 

  use FindBin; 
  my $fatbin = "$FindBin::Bin/../bin/exc"; 
  require $fatbin if -f $fatbin;

  use lib 'local/lib/perl5';
}

use Test::More;
use Test::Deep; 


use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  
use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

use Text::Diff;
use File::Path qw( make_path rmtree );

use_ok('App::RaffiWare::ExCollect::Cmd::Watcher');
 
my $runner_cmd = App::RaffiWare::ExCollect::Cmd::Watcher->new( 
                      argv     => [], 
                      cfg_file => 't/excollect/exc.cfg',
                      cmd_dir  => 't/excollect/cmd/runner/' );

isa_ok($runner_cmd, 'App::RaffiWare::ExCollect::Cmd::Watcher');

done_testing();
