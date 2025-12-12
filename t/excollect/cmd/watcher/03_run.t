#!/usr/bin/env perl
#
use strict;
use warnings;

BEGIN { 

  require App::RaffiWare::ExCollect::Worker; 

  use lib qw|t/lib|;
  use Test::ExCollectWorker; # disabled command_verification 

  $ENV{PATH} = './bin:'. $ENV{PATH}; 
}; 

use Test::More;
use Test::Deep; 

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  
use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

use AnyEvent;
use AnyEvent::Fork; 
use Text::Diff;
use File::Path qw( make_path rmtree );

use App::RaffiWare::ExCollect::Cmd::Watcher;

App::RaffiWare::Logger->instance( level => 'debug' );   

my $watcher_cmd = App::RaffiWare::ExCollect::Cmd::Watcher->new( 
  worker_template_class => 'Test::ExCollectWorker',  
  debug    => 1,
  argv     => ['start', '--no-daemonize', '--max-startup-delay=0' ], 
  cfg_file => 't/excollect/exc.cfg',
  cmd_dir  => 't/excollect/cmd/watcher' 
); 
 

my $job_id = 'chj_4939142ff0b04239b67e71d160c3694f';

mkdir 't/excollect/cmd/watcher/jobs'; 
mkdir 't/excollect/cmd/watcher/replay_cache';
mkdir 't/excollect/cmd/watcher/archive';  

rmtree "t/excollect/cmd/watcher/jobs/$job_id";
rmtree "t/excollect/cmd/watcher/archive/$job_id"; 

my $job = App::RaffiWare::ExCollect::Job->init(
  { 
     id             => $job_id,
     status         => 'queued',
     command_string => '/bin/uptime',
     priority       => 1,
     instance => {
        execute_type => 'bin'
     } 
  },
  cfg_file   => 't/excollect/exc.cfg',
  cmd_dir    => 't/excollect/cmd/watcher' 
); 


my $w = AE::timer 3, 0, sub { diag "Shutting down"; $watcher_cmd->shutdown(); };

$watcher_cmd->run();

$job->reload_job_state();

my $status = $job->get_job_val('status');

is $status, 'complete', 'job status complete';

done_testing(); 
