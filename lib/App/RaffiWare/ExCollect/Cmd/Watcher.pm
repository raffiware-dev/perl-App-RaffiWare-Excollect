# ./script/exc.PL watcher
package App::RaffiWare::ExCollect::Cmd::Watcher;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use App::RaffiWare::Logger;

use AnyEvent;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;
use English qw( -no_match_vars );
use Data::Dumper;
use File::Which;
use JSON qw| decode_json encode_json |;
use Proc::Daemon;

with 'App::RaffiWare::Role::IsCmd',
     'App::RaffiWare::Role::HasAPIClient',
     'App::RaffiWare::ExCollect::Role::HasJobs';

has '+api_class' => ( default => sub { 'App::RaffiWare::ExCollect::API' } );

has 'max_workers' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_max_workers',
  default => sub { shift->cmd_cfg->get('max_workers') || 2 }
);

has 'job_poll_interval' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_job_poll_interval',
  default => sub { shift->cmd_cfg->get('job_poll_interval') || 60 }
);

has 'replay_check_interval' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_replay_check_interval',
  default => sub { shift->cmd_cfg->get('replay_check_interval') || 120 }
);

has 'no_daemonize' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_no_daemonize'
);

has 'daemon' => (
  is      => 'ro',
  isa     => InstanceOf ['Proc::Daemon'],
  lazy    => 1,
  builder => '_build_daemon',
  handles => {
    init_daemon   => 'Init',
    daemon_status => 'Status',
  }
);

sub _build_daemon {
  my $self = shift;

  return Proc::Daemon->new( 
           work_dir => $self->cmd_dir, 
           pid_file => $self->cmd_dir . '/watcher.pid' 
         );
}

sub stop_daemon {
  my $self = shift;

  $self->daemon->Kill_Daemon( '', 'TERM' );
}

has 'init_only' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_init_only'
);

sub _build_get_opts {
  [
    qw|
      job-poll-interval=i
      replay-check-interval=i
      max-workers=i
      init-only
      no-daemonize
    |
  ]
}

has 'sub_action' => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_sub_action',
  writer    => '_set_sub_action'
);

sub _build_pos_args {
  [ [ '_set_sub_action', 'Invalid Action', sub { shift }, 1 ] ]
}

sub run {
  my ($self) = @_;

  if ( !$self->has_sub_action ) {
    warn $self->get_help_data();
    return 1;
  }

  my $action     = $self->sub_action;
  my $action_sub = "do_$action";

  return $self->$action_sub() if $self->can($action_sub);

  warn("Invalid action '$action'\n");
  return 1;
}

sub do_start {
  my ($self) = @_;

  if ( my $pid = $self->daemon_status ) {
    warn "\nWatcher already running with PID $pid\n\n";
    return 1;
  }

  if ( $self->no_daemonize ) {

    # Write out the pid as Proc::Daemon would so any other instances
    # trying to start will see we are already running.
    my $pid_file = $self->daemon->{pid_file};

    open( my $FH_PIDFILE, "+>", $pid_file ) || FATAL("Can not open pidfile (pid_file => '$pid_file'): $!");

    print $FH_PIDFILE $PID;

    close $FH_PIDFILE;
  }
  else {
    # Parent returns after checking daemon status.
    if ( my $pid = fork() ) {
      sleep 2;
      my $daemon_pid = $self->daemon_status;

      warn "\n Watcher process not started\n\n" if !$daemon_pid;

      return $daemon_pid ? 0 : 1;
    }
    elsif ( defined $pid ) {
      $self->init_daemon;
    }
    else {
      FATAL("Failed fork before daemonizing: $!");
    }
  }

  INFO("Starting Watcher");

  $self->queue_existing_jobs();
  $self->init_job_fetcher();
  $self->init_replay_check();

  $self->start_event_loop();

}

sub do_stop {
  my ($self) = @_;

  if ( !$self->daemon_status ) {
    warn "\nWatcher not running\n\n";
    return 1;
  }

  $self->stop_daemon();

  return 0;
}

sub do_restart {
  my ($self) = @_;

  $self->do_stop;
  $self->do_start;
}

sub do_status {
  my ($self) = @_;

  if ( my $pid = $self->daemon_status ) {
    print "\nWatcher running with pid $pid\n\n";
  }
  else {
    print "\nWatcher not running\n\n";
  }
  return 0;
}

sub queue_existing_jobs {
  my ($self) = @_;

  foreach my $job ( @{ $self->jobs } ) {
    $self->queue_job($job);
  }

}

sub queue_job {
  my ( $self, $job ) = @_;

  return if !$job->lock();

  $job->reload_job_state();

  return if $job->get_job_val('status') ne 'queued';

  return if $self->init_only;

  $self->worker_pool->(
    job      => $job->job_id,
    cmd_dir  => $job->cmd_dir,
    cfg_file => $job->cfg_file,
    debug    => $self->debug,
    sub { DEBUG("Worker returned for job @_") }
  );

  $job->unlock();

  INFO( "Queued " . $job->job_id );
}

has 'job_fetch_timer' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  clearer => '_clear_job_fetch_timer',
  builder => '_build_job_fetch_timer'
);

sub _build_job_fetch_timer {
  my ($self) = @_;

  # Slightly randomize the job poll time to reduce herding
  # if a large number of clients agents start at once..
  my @pad_range = (-10..10);
  my $interval  = $self->job_poll_interval + $pad_range[int(rand(@pad_range))];

  return AE::timer 0, $interval,
           sub {
             DEBUG("Checking for new jobs");

             my $jobs_collection = $self->api->get_jobs() or return; 

             foreach my $job ( @{$jobs_collection->{collection}} ) {

               if ( $self->load_job( $job->{id} ) ) {
                 WARNING( sprintf( 'Job %s already fetch', $job->{id} ) );
                 next;
               }

               INFO( sprintf( "Got new job %s", $job->{id} ) );
               DEBUG( Dumper( $job ) );

               my $job = $self->init_job( $job );

               $self->queue_job($job); 

             }
           };

}

sub init_job_fetcher { shift->job_fetch_timer }

has 'replay_check_timer' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  clearer => '_clear_replay_check_timer',
  builder => '_build_replay_check_timer'
);

sub _build_replay_check_timer {
  my ($self) = @_;

  return AE::timer 0, $self->replay_check_interval, 
           sub {
             DEBUG("Checking for replay requests");

             $self->worker_pool->(
               'replay_check',
               cmd_dir  => $self->cmd_dir,
               cfg_file => $self->cfg_file,
               debug    => $self->debug,
               sub { DEBUG("Replay Check Worker returned @_") }
             );

           };

}

sub init_replay_check { shift->replay_check_timer }

has 'worker_template' => (
  is      => 'ro',
  isa     => InstanceOf ['AnyEvent::Fork'],
  lazy    => 1,
  builder => '_build_worker_template'
);

sub _build_worker_template {
  my ($self) = @_;

  return AnyEvent::Fork->new->require('App::RaffiWare::ExCollect::Worker');
}

has 'ae_cv' => (
  is      => 'ro',
  isa     => InstanceOf ['AnyEvent::CondVar'],
  default => sub { AE::cv },
  handles => {
    start_event_loop => 'recv'
  }
);

has 'worker_pool' => (
  is      => 'ro',
  isa     => CodeRef,
  lazy    => 1,
  builder => 'init_worker_pool',
  clearer => '_shutdown_pool',
  writer  => '_set_worker_pool'
);

sub init_worker_pool {
  my ($self) = @_;

  # Force AnyEvent::Fork to use our
  # binary to spawn worker processes.
  # On binary installed systems this
  # will be a self container PAR executable.
  my $anyevent_fork_bin = File::Which::which("anyevent-fork") or FATAL("anyevent-fork not in PATH");
  $AnyEvent::Fork::PERL = $anyevent_fork_bin;

  return $self->worker_template
              ->AnyEvent::Fork::Pool::run(
                 'App::RaffiWare::ExCollect::Worker::run',

                  # pool management
                  max        => $self->max_workers,    # absolute maximum # of processes
                  idle       => 0,                     # minimum # of idle processes
                  load       => 1,                     # queue at most this number of jobs per process
                  start      => 0.1,                   # wait this many seconds before starting a new process
                  stop       => 10,                    # wait this many seconds before stopping an idle process
                  on_destroy => $self->ae_cv,          # called when object is destroyed
                );
}

sub shutdown {
  my ($self) = @_;

  $self->_clear_job_fetch_timer;
  $self->_clear_replay_check_timer;
  $self->_shutdown_pool;
}

1;

__DATA__

=head1 SYNOPSIS

exc watcher <COMMAND> [OPTIONS ...] 

=head1 EXAMPLE
 
  exc watcher start

=head1 SUB COMMANDS

=over 4 

=item start

=item stop

=item restart

=item status

=back 

=head1 OPTIONS

=over 4

=item --no-daemonize 

Do not background watcher process on start

=item --help 

Print this document

=item --job-poll-interval=i 

Base interval period between checking for new jobs.  

=item  --max-workers=i

Maximum number of worker processes running jobs. 

=item --replay-check-interval=i

Time in seconds between checking the replay cache. 

=back

=head1 CONFIGURATION

=over 4

=item job_poll_interval=i 

Base interval period between checking for new jobs. 

=item max_workers=i

Maximum number of worker processes running jobs.

=item replay_check_interval=i

Time in seconds between checking the replay cache.

=back 

=cut  

