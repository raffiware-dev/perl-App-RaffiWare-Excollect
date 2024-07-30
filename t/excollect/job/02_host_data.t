#!/usr/bin/env perl
use strict;
use warnings;

BEGIN { 

  use FindBin;
  my $fatbin = "$FindBin::Bin/../bin/exc"; 
  require $fatbin if -f $fatbin;

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


my $job_id = 'chj_1939342ff0b04239b67e71d160c3694f';

rmtree "t/excollect/job/jobs/$job_id";
rmtree "t/excollect/job/archive/$job_id";

mkdir 't/excollect/job/jobs';

my $job = App::RaffiWare::ExCollect::Job->init(
              { 
                 id           => $job_id,
                 client_name  => 'TestingClient',
                 status       => 'queued',
                 command_string => q|/bin/echo -n '#CV-ClientName-CV# #CV-OperatingSystem-CV#'|,
                 priority     => 1,

              },
              cfg_file   => 't/excollect/exc.cfg',
              cmd_dir    => 't/excollect/job' );


isa_ok($job, 'App::RaffiWare::ExCollect::Job'); 

$job->execute();

my $stdout_file = $job->job_logger->stdout_file;
my $stdout = do { local $/ = undef; open my $stdout_fh, '<', $stdout_file; <$stdout_fh> };

is $stdout, 'TestingClient debian', 'Client Variables set in final command';
 

done_testing();
