# ./script/exc.PL run 
package App::RaffiWare::ExCollect::Worker;

use strict;
use warnings; 

use App::RaffiWare::Logger;

use Cwd;
use Moo; 
use Proc::Daemon;
use Types::Standard qw| :all |;
 
with  'App::RaffiWare::Role::HasCfg',
      'App::RaffiWare::Role::HasLogger', 
      'App::RaffiWare::Role::HasAPIClient', 
      'App::RaffiWare::ExCollect::Role::HasJobs';

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

sub run {
    my ( $work_type, @args ) = @_;

    if ( $work_type eq 'job' ) {
        return run_job(@args);
    }
    elsif ( $work_type eq 'replay_check' ) {
        return run_replay(@args);
    }

}

sub run_job {
    my ( $job_id, %wargs ) = @_; 

    my $worker = init_worker(%wargs); 

    my $job = $worker->load_job($job_id);

    my $daemon = Proc::Daemon->new( 
                   work_dir => getcwd(), 
                   pid_file => $job->cmd_dir .'/jobs/'. $job->job_id .'.pid',
                   child_STDOUT => '+>>'. $job->cmd_dir .'/jobs/'. $job->job_id .'/logs/log',
                   child_STDERR => '+>>'. $job->cmd_dir .'/jobs/'. $job->job_id .'/logs/log.err'
                 );

    # We create a daemon for the job to execute in so if the watcher process is killed
    # the job will finish executing. We still want to try and poll for when the daemon 
    # exits so we hold a spot in the worker pool while the job is running.
    my $pid = $daemon->Init() // die ('failed to daemonize');

    unless ($pid) {
        $job->execute();

        exit(0); 
    }

    sleep 2;

    while (my $status = $daemon->Status) { sleep 1 }

    return $job_id;
}

sub run_replay {
    my ( %wargs ) = @_;

    my $worker = init_worker(%wargs);

    $worker->api->run_replay_requests();
}

sub init_worker {
    my ( %wargs ) = @_;

    my $debug = delete $wargs{debug};

    my $worker = __PACKAGE__->new(%wargs);

    $worker->set_level('debug') if $debug; 
    $worker->logger(); 

    return $worker;
}

1;
