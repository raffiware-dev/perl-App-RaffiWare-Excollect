#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { 

  require App::RaffiWare::ExCollect::Worker; 

  use lib qw|t/lib|;
  use Test::ExCollectWorker; # disabled command_verification

}; 

use Test::More;
use Test::Deep; 

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  
use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

use Text::Diff;
use File::Path qw( make_path rmtree );

use_ok('App::RaffiWare::ExCollect::Job');


App::RaffiWare::Logger->instance( level => 'debug' );  


my $job_id = 'chj_2939542gf0b04239b67e71d160c3694f';

rmtree "t/excollect/job/jobs/$job_id";
rmtree "t/excollect/job/archive/$job_id";

mkdir 't/excollect/job/jobs';

my $job = App::RaffiWare::ExCollect::Job->init(
  { 
     id             => $job_id,
     status         => 'queued',
     command_string => '/bin/uptime',
     priority       => 1,
     instance => {
        execute_type   => 'bin',
     }
  },
  cfg_file   => 't/excollect/exc.cfg',
  cmd_dir    => 't/excollect/job' 
);


isa_ok($job, 'App::RaffiWare::ExCollect::Job'); 

$job->execute();

my $stdout_file = $job->job_logger->stdout_file;
my $stdout = do { local $/ = undef; open my $stdout_fh, '<', $stdout_file; <$stdout_fh> };

like $stdout, qr/load average/, 'got STDOUT of exec';


my $status = $job->get_job_val('status');

is $status, 'complete', 'job status complete';
ok  $job->get_job_val('pid'), 'pid set';
ok  defined $job->get_job_val('exit'), 'exit set'; 


$job_id = 'chj_5139142ff0b04239b67e71d160c3693e';

rmtree "t/excollect/job/jobs/$job_id"; 
rmtree "t/excollect/job/archive/$job_id"; 

$job = App::RaffiWare::ExCollect::Job->init(
  { 
     id             => $job_id,
     status         => 'queued',
     command_string => q|/usr/bin/env perl -e 'print "Hello World\n"; die("Goodbye World\n")'  |,
     priority       => 1,
     instance => {
        execute_type   => 'bin',
     } 
  },
  cfg_file   => 't/excollect/exc.cfg', 
  cmd_dir    => 't/excollect/job' 
);

$job->execute();

$stdout_file = $job->job_logger->stdout_file; 
my $stderr_file = $job->job_logger->stderr_file;  

$stdout = do { local $/ = undef; open my $stdout_fh, '<', $stdout_file; <$stdout_fh> };
like $stdout, qr/Hello World/, 'got STDOUT of exec'; 
diag $stdout;

my $stderr = do { local $/ = undef; open my $stderr_fh, '<', $stderr_file; <$stderr_fh> };  
like $stderr, qr/Goodbye World/, 'got STDERR of exec';  
diag "$stderr";

$status = $job->get_job_val('status');

is $status, 'error', 'job status error'; 

done_testing();

