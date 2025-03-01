#!/usr/bin/env perl
use strict;
use warnings;

BEGIN { 

  use FindBin;
  my $fatbin = "$FindBin::Bin/../bin/exc"; 
  require $fatbin if -f $fatbin;

  use App::RaffiWare::ExCollect::Worker;  

  no warnings 'redefine';
  *App::RaffiWare::ExCollect::Job::verify_command_signature = sub { warn('no command verification'); 1 };
 
}; 

use Test::More;
use Test::Deep; 

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  
#use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

use Text::Diff;
use File::Path qw( make_path rmtree );

use_ok('App::RaffiWare::ExCollect::Worker');


App::RaffiWare::Logger->instance( level => 'debug' );  


my $job_id = 'chj_4939142ff0b04239b67e71d160c3694f';
my $job2_id = 'chj_5939142ff0b04239b67e71d160c3694f';

rmtree "t/excollect/worker/jobs/$job_id";
rmtree "t/excollect/worker/jobs/$job2_id";
mkdir 't/excollect/worker/jobs';


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
              cmd_dir    => 't/excollect/worker' );
 

my $ret = App::RaffiWare::ExCollect::Worker::run( 
              job     => $job->job_id,
              cmd_dir => $job->cmd_dir,
              cmd_cfg => $job->cmd_cfg );

diag $ret;

$job->reload_job_state();

my $status = $job->get_job_val('status');

is $status, 'complete', 'job status complete'; 

diag "longer command, this will take 20 seconds ...";
$job = App::RaffiWare::ExCollect::Job->init(
              { 
                 id             => $job2_id,
                 status         => 'queued',
                 command_string => q|bash -c "sleep 10; echo 'done'"|,
                 priority       => 1,
                 instance => {
                    execute_type => 'bin'
                 } 
              },
              cfg_file   => 't/excollect/exc.cfg',
              cmd_dir    => 't/excollect/worker' );
 

$ret = App::RaffiWare::ExCollect::Worker::run( 
              job     => $job->job_id,
              cmd_dir => $job->cmd_dir,
              cmd_cfg => $job->cmd_cfg );

diag $ret;

$job->reload_job_state();

$status = $job->get_job_val('status');

is $status, 'complete', 'job status complete';  

done_testing(); 
