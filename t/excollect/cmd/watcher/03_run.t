#!/usr/bin/env perl
use strict;
use warnings;

BEGIN { 

  #use FindBin;
  #my $fatbin = "$FindBin::Bin/../bin/exc"; 
  #require $fatbin if -f $fatbin;

  use lib 'local/lib/perl5'; 
  use lib 't/lib'; 

  use App::RaffiWare::ExCollect::Worker; 

  no warnings 'redefine';
  *App::RaffiWare::ExCollect::Job::verify_command_signature = sub { warn('no command verification'); 1 };

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

my $wt = AnyEvent::Fork->new->require('Test::ExCollectWorker');  

my $watcher_cmd = App::RaffiWare::ExCollect::Cmd::Watcher->new( 
                      worker_template => $wt,  
                      debug    => 1,
                      argv     => ['start', '--no-daemonize'], 
                      cfg_file => 't/excollect/exc.cfg',
                      cmd_dir  => 't/excollect/cmd/watcher' ); 
 

my $job_id = 'chj_4939142ff0b04239b67e71d160c3694f';

mkdir 't/excollect/cmd/watcher/jobs'; 
mkdir 't/excollect/cmd/watcher/archive';  

rmtree "t/excollect/cmd/watcher/jobs/$job_id";
rmtree "t/excollect/cmd/watcher/archive/$job_id"; 

my $job = App::RaffiWare::ExCollect::Job->init(
              { 
                 id             => $job_id,
                 status         => 'queued',
                 command_string => '/bin/uptime',
                 priority       => 1,

              },
              cfg_file   => 't/excollect/exc.cfg',
              cmd_dir    => 't/excollect/cmd/watcher' ); 


my $w = AE::timer 3, 0, sub { diag "Shutting down"; $watcher_cmd->shutdown(); };

$watcher_cmd->run();

$job->reload_job_state();

my $status = $job->get_job_val('status');

is $status, 'complete', 'job status complete';  

done_testing(); 
