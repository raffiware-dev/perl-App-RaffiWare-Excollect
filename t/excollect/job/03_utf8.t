#!/usr/bin/env perluse strict;
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

rmtree "t/excollect/job/jobs";
mkdir 't/excollect/job/jobs';

my $job_id = 'chj_4729542gf0b04239b67e71d160c3694e';


my $pushkin =<<'END';
На берегу пустынных волн
Стоял он, дум великих полн,
И вдаль глядел. Пред ним широко
Река неслася; бедный чёлн
По ней стремился одиноко.
По мшистым, топким берегам
Чернели избы здесь и там,
Приют убогого чухонца;
И лес, неведомый лучам
В тумане спрятанного солнца,
Кругом шумел.
END

my $job = App::RaffiWare::ExCollect::Job->init(
              { 
                 id             => $job_id,
                 status         => 'queued',
                 command_string => qq|/usr/bin/echo -n "$pushkin"|,
                 priority       => 1,
                 instance => {
                    execute_type   => 'bin',
                 }
              },
              cfg_file   => 't/excollect/exc.cfg',
              cmd_dir    => 't/excollect/job' );


isa_ok($job, 'App::RaffiWare::ExCollect::Job'); 

$job->execute();

my $stdout_file = $job->job_logger->stdout_file;
my $stdout = do { local $/ = undef; open my $stdout_fh, '<', $stdout_file; <$stdout_fh> };

#chomp $stdout;
is $stdout, $pushkin, 'UTF-8 STDOUT';


my $status = $job->get_job_val('status');

is $status, 'complete', 'job status complete'; 


my $rune=<<'END';
ᚠᛇᚻ᛫ᛒᛦᚦ᛫ᚠᚱᚩᚠᚢᚱ᛫ᚠᛁᚱᚪ᛫ᚷᛖᚻᚹᛦᛚᚳᚢᛗ
ᛋᚳᛖᚪᛚ᛫ᚦᛖᚪᚻ᛫ᛗᚪᚾᚾᚪ᛫ᚷᛖᚻᚹᛦᛚᚳ᛫ᛗᛁᚳᛚᚢᚾ᛫ᚻᛦᛏ᛫ᛞᚫᛚᚪᚾ
ᚷᛁᚠ᛫ᚻᛖ᛫ᚹᛁᛚᛖ᛫ᚠᚩᚱ᛫ᛞᚱᛁᚻᛏᚾᛖ᛫ᛞᚩᛗᛖᛋ᛫ᚻᛚᛇᛏᚪᚾ᛬
END

$job_id = 'chj_75t9542gf0b04239b67e71d160c3694b'; 


$job = App::RaffiWare::ExCollect::Job->init(
              { 
                 id             => $job_id,
                 status         => 'queued',
                 command_string => qq|/bin/bash -c 'echo -n "$rune" 1>&2'|,
                 priority       => 1,
                 instance => {
                    execute_type   => 'bin',
                 }
              },
              cfg_file   => 't/excollect/exc.cfg',
              cmd_dir    => 't/excollect/job' );


isa_ok($job, 'App::RaffiWare::ExCollect::Job'); 

$job->execute();

$stderr_file = $job->job_logger->stderr_file;
$stderr = do { local $/ = undef; open my $stderr_fh, '<', $stderr_file; <$stderr_fh> };

diag $stderr;

is $stderr, $rune, 'UTF-8 STDERR';


$status = $job->get_job_val('status');

is $status, 'complete', 'job status complete'; 
 
 
 

done_testing(); 
