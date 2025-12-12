# ./script/exc.PL watcher
package App::RaffiWare::ExCollect::Cmd::Watcher;

use strict;
use warnings;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw| :all |;

use App::RaffiWare::Logger;

use AnyEvent;
use AnyEvent::Handle; 
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;
use AnyEvent::WebSocket::Client;
use FindBin;
use File::Which;
use JSON qw| decode_json encode_json |;
use POSIX ":sys_wait_h"; 
use Proc::Daemon;
use Try::Tiny;

with 'App::RaffiWare::Role::IsCmd',
     'App::RaffiWare::ExCollect::Role::HasJobs';

has 'max_workers' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_max_workers',
  default => sub { shift->cmd_cfg->get('max_workers') }
);

has 'timer_check_interval' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_timer_check_interval',
  default => sub { shift->cmd_cfg->get('timer_check_interval')  }
);

has 'job_poll_interval' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_job_poll_interval',
  default => sub { shift->cmd_cfg->get('job_poll_interval') }
);

has 'replay_check_interval' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  writer  => '_set_replay_check_interval',
  default => sub { shift->cmd_cfg->get('replay_check_interval') }
);

has 'ws_client_ping_interval' => (
  is        => 'ro',
  isa       => Int,
  lazy    => 1, 
  writer  => '_set_ws_client_ping_interval', 
  default => sub { shift->cmd_cfg->get('ws_ping_interval')  }
);

has 'max_startup_delay' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1, 
  writer  => '_set_max_startup_delay', 
  default => sub { shift->cmd_cfg->get('max_startup_delay') }
); 

has 'no_daemonize' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_no_daemonize'
);

has 'is_daemon' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_daemon'
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
      timer-check-interval=i
      ws-client-ping-interval=i
      max-startup-delay=i
      max-workers=i
      init-only
      no-daemonize
      daemon
    |
  ]
}

sub _build_pos_args {
  [ [ '_set_sub_action', 'Invalid Action', sub { shift }, 1 ] ]
}

has 'sub_action' => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_sub_action',
  writer    => '_set_sub_action'
);

my $EXIT_OK  = 0;
my $EXIT_ERR = 1; 

sub run {
  my ($self) = @_;

  if ( !$self->has_sub_action ) {
    warn $self->get_help_data();

    return $EXIT_ERR;
  }

  my $action     = $self->sub_action;
  my $action_sub = "do_$action";

  return $self->$action_sub() if $self->can($action_sub);

  warn("Invalid action '$action'\n");

  return $EXIT_ERR;
}

sub do_start {
  my ($self) = @_;

  if ( $self->is_daemon ) {

    return $self->start_watcher();
  }

  if ( my $pid = $self->daemon_status ) {

    warn "\nWatcher already running with PID $pid\n\n";

    return $EXIT_ERR;
  }

  if ( $self->no_daemonize ) {

    # Write out the pid as Proc::Daemon would so any other instances
    # trying to start will see we are already running.
    my $pid_file = $self->daemon->{pid_file};

    open( my $FH_PIDFILE, "+>", $pid_file ) 
      or die("Can not open pidfile (pid_file => '$pid_file'): $!\n");

    print $FH_PIDFILE $$;

    close $FH_PIDFILE;

    return $self->start_watcher();
  }

  # Even with exec_command Proc::Daemon::Init forks and re parents 
  # so we fork first and monitor the status to check for startup 
  # errors and return them to the terminal.
  if ( my $pid = fork() ) {

    my $count = 5;
    sleep 1 while ( $count-- and !$self->daemon_status );

    warn "\n Watcher process not started\n\n" if !$self->daemon_status; #  $daemon_pid;

    return $self->daemon_status ? $EXIT_OK : $EXIT_ERR;
  }
  elsif ( defined $pid ) {

    # We have to start a new instance to play nice with
    # AnyEvent::Fork::Early
    my $daemon_pid = $self->init_daemon({ 
      exec_command => [ "$FindBin::Bin/$FindBin::RealScript watcher start --daemon" ] 
    });

    return $daemon_pid ? $EXIT_OK : $EXIT_ERR; 
  }
  else {
    die("Failed fork before daemonizing: $!\n");
  }
}

sub do_stop {
  my ($self) = @_;

  if ( !$self->daemon_status ) {

    warn "\nWatcher not running\n\n";

    return $EXIT_ERR;
  }

  $self->stop_daemon();

  return $EXIT_OK;
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

  return $EXIT_OK;
}

my $term_reaper;
sub start_watcher {
  my ($self) = @_;

  {
    local $SIG{__DIE__}; # Quiet AE trying to load optional stuff 
    $term_reaper = AnyEvent->signal(
       signal => "TERM", 
       cb => sub { 

         WARNING('Got SigTerm');

         # Wait for AE children so Systemd 
         # doesn't complain.
         1 while waitpid(-1, WNOHANG) > 0; 

         INFO('Shutting down');
         exit(0);
       });
  }

  DEBUG('Watcher Settings'); 
  foreach (qw|
     max_workers
     timer_check_interval
     job_poll_interval
     replay_check_interval
     ws_client_ping_interval
     max_startup_delay
  |) {
     DEBUG(sprintf('  %-30s : %s', $_, $self->$_ ) );
  }

  # Random delay on start up to mitigate thundering herds.
  my @delay_range = (0 .. $self->max_startup_delay);
  my $delay       =  $delay_range[int(rand(@delay_range))];

  INFO("Delaying start up requests $delay seconds");

  my $st = AE::timer $delay, 0, sub { 

    INFO("Starting Watcher");

    $self->queue_existing_jobs();
    $self->init_websocket_client(); 

    $self->replay_cache(); 
    $self->fetch_jobs();

    $self->init_timer_check();
  };

  $self->start_event_loop(); 
}

sub queue_existing_jobs {
  my ($self) = @_;

  foreach my $job_id ( @{ $self->jobs } ) {
    $self->queue_job($job_id);
  }
}

sub queue_job {
  my ( $self, $job_id ) = @_;

  return if $self->init_only;

  $self->fork_worker(  
    job       => $job_id,
    cmd_dir   => $self->cmd_dir,
    cfg_file  => $self->cfg_file,
    log_level => $self->log_level,
    sub { TRACE("Worker returned for job @_") }
  ); 

  # Pool has an high memory cost that's not
  # work it for most uses. Might resurrect this 
  # later there's a demand for it.
  #$self->worker_pool->(
  #  job      => $job_id,
  #  cmd_dir  => $self->cmd_dir,
  #  cfg_file => $self->cfg_file,
  #  debug    => $self->debug,
  #  sub { DEBUG("Worker returned for job @_") }
  #);

}

has 'last_timer_check' => (
  is      => 'rw',
  isa     => HashRef[Int],
  handles_via => 'Hash', 
  default => sub { 
    my $ts = time; 

    +{ fetch_jobs   => $ts, 
       replay_cache => $ts, 
       ws_ping      => $ts 
    }
  },
  handles => {
    get_last_check => 'get',
    set_last_check => 'set',
  } 
);

has 'check_timer' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  clearer => '_clear_timer',
  builder => '_build_check_timer'
);

sub _build_check_timer {
  my ($self) = @_;

  return AE::timer 
    $self->timer_check_interval,
    $self->timer_check_interval,
    sub {

      TRACE("Checking for timer actions");

      $self->init_websocket_client;

      my $ts = time;

      $self->replay_cache_timer($ts);
      $self->fetch_jobs_timer($ts);
      $self->ws_ping_timer($ts);

    };
}

sub init_timer_check { shift->check_timer } 

has 'ws_client_cbs' => (
  is        => 'ro',
  isa       => HashRef,
  default   => sub { +{} },
  handles_via => 'Hash',
  handles => {
    get_msg_cb => 'get',
    set_msg_cb => 'set',
  }
);

has '_ws_client' => (
  is        => 'ro',
  isa       => ArrayRef,
  writer    => '_set_ws_client',
  predicate => 'has_ws_client',
  clearer   => '_clear_ws_client'
); 

my $connect_in_progress;
sub ws_client {
  my ( $self ) = @_;

  $self->init_websocket_client;

  my $ret = $self->has_ws_client ? $self->_ws_client : [];

  return $ret;
}

my $quick_auth;
sub init_websocket_client {
  my ( $self ) = @_;

  $quick_auth = undef;

  return if ($connect_in_progress || $self->has_ws_client);

  $connect_in_progress = 1;

  #$self->worker_pool->(
  $self->fork_worker(
    'get_ws_token',
    cmd_dir   => $self->cmd_dir,
    cfg_file  => $self->cfg_file,
    log_level => $self->log_level,
    sub { 
      my $token = shift;

      if ( !$token ) {
        ERROR('Failed to get websocket token');

        $connect_in_progress = 0; 
        return;
      }

      TRACE("Got Websocket Token $token");

      my $cb = sub {

        my $connection = eval { local $SIG{__DIE__}; shift->recv };

        $connect_in_progress = 0;

        if ($@) {

          WARNING("Websocket error: $@");
          return;
        } 

        INFO('Websocket Connected');

        $self->_set_ws_client([$connection, \(my $base_ident = 1) ]);

        $connection->on( each_message => sub {
          my ( $connection, $message ) = @_;

          TRACE('Got message - '. $message->body  );

          my $data = eval { decode_json($message->body) } || {};

          if ( my $err = $data->{error} ) {

            ERROR("WS Error: $err");

            if ( $err eq 'auth failed' ) {

              $self->clear_ws_token();

              my @delay_range = (5 .. 15);
              my $delay       = $delay_range[int(rand(@delay_range))];

              $quick_auth = AE::timer $delay, 0, sub { 

                TRACE("Quick Updating Expired Websocket Token");

                $self->init_websocket_client(); 
              };
            }

            $self->_clear_ws_client; 
            return;
          }

          if ( $data->{ident} 
            and my $cb = $self->get_msg_cb($data->{ident}) 
          ) {

            $cb->($connection, $data);
          }

          my $cmd = $data->{cmd} || $data->{return} or return;

          if ( ($cmd eq 'spawn_shell')
            || ($cmd eq 'shell_in')
          ) {

            TRACE("shell cmd :$cmd");
            $self->init_shell_mgr( 
              sub { 
                 $self->shell_mgr_writer->push_write( json => $data ) 
              }); 
          }
          elsif ( $cmd eq 'poll_jobs' ) {

            TRACE("poll_jobs cmd");

            $self->fetch_jobs();
          }
          elsif ( $cmd eq 'ping' ) {
            TRACE('WS '. $data->{data});
          }
          else{
            WARNING("Unknown command: $cmd");
          }

        });

        $connection->on( finish => sub {
          my ($connection) = @_;

          WARNING( "WS Closed" );
          $self->_clear_ws_client;
        });

      };

      $connect_in_progress = 0
        if !$self->get_ws_connection($token, $cb); 
    }
  );
}

sub get_ws_connection {
  my ($self, $token, $cb) = @_;

  my $endpoint = $self->get_cfg_val('exc_ws_endpoint'); 
  my $id       = $self->get_cfg_val('client_id');

  return if !$endpoint;

  my $client = AnyEvent::WebSocket::Client->new(
    timeout      => 30,
    http_headers => [ 'EXC-KEYID' => $id, 'EXC-AUTH' => $token ] 
  ); 

  $client->connect(sprintf("%s/client/%s/control", $endpoint, $id ))
         ->cb($cb);

  return $client;
}

sub clear_ws_token {
  my $self = shift; 

  $self->set_cfg_val( exc_ws_token => '' ); 
} 

sub send_ws_msg {
  my ( $self, $msg, $send_ident, $cb ) = @_; 

  my ( $connection, $ident ) = @{$self->ws_client};

  return if !$connection;

  $self->set_msg_cb( $$ident, $cb ) if $cb;

  TRACE("raw data:". $msg->{data} ) if $msg->{data};

  my $final_msg = JSON->new()->utf8(1)->encode({
    $send_ident ? ( ident => ${$ident}++) : (),
    %$msg 
  });

  TRACE("Sending message $final_msg");

  $connection->send($final_msg);
}

has 'shell_mgr_pipes' => (
  is      => 'ro',
  isa     => ArrayRef[FileHandle],
  lazy    => 1,
  builder => '_build_shell_mgr_pipes',
);

sub _build_shell_mgr_pipes {
  my $self = shift;

  pipe my $from_parent, my $to_child;
  pipe my $from_child, my $to_parent;

  $to_child->autoflush(1);
  $to_parent->autoflush(1);

  return [ $from_parent, $to_child, $from_child, $to_parent ]
}

sub shell_mgr_from_parent { shift->shell_mgr_pipes->[0] }
sub shell_mgr_to_child    { shift->shell_mgr_pipes->[1] }
sub shell_mgr_from_child  { shift->shell_mgr_pipes->[2] }
sub shell_mgr_to_parent   { shift->shell_mgr_pipes->[3] }

has 'shell_mgr_reader' => (
  is        => 'ro',
  isa       => InstanceOf['AnyEvent::Handle'],
  lazy      => 1,
  builder   => '_build_shell_mgr_reader',
  clearer   => '_clear_shell_mgr_reader'
); 

sub _build_shell_mgr_reader {
  my $self = shift; 

  binmode($self->shell_mgr_from_child);

  my $hdl = new AnyEvent::Handle
    fh      => $self->shell_mgr_from_child,
    on_read => sub {
      my ($hdl) = @_;

      $hdl->unshift_read(json => sub {
        my ($hdl, $data ) = @_;

        if ($data->{return} || $data->{shell_event} ) {
            $self->send_ws_msg($data, 1);
            return;
        }

        my $cmd = $data->{cmd} or return;

        if ( $cmd eq 'shell_out' ) {
            $self->send_ws_msg($data)
        }
      });
    },
    on_error => sub {
      my ($hdl, $fatal, $msg) = @_;

      ERROR("Shell Manager Reader - $msg");
      $hdl->destroy;
    },
    on_eof => sub {
      TRACE("Shell Manager Reader EOF");
    }; 

  return $hdl
}

has 'shell_mgr_writer' => (
  is        => 'ro',
  isa       => InstanceOf['AnyEvent::Handle'],
  lazy      => 1, 
  builder   => '_build_shell_mgr_writer',
  clearer   => '_clear_shell_mgr_writer'
); 

sub _build_shell_mgr_writer {
  my $self = shift; 

  my $hdl = new AnyEvent::Handle
    fh       => $self->shell_mgr_to_child,
    on_error => sub {
      my ($hdl, $fatal, $msg) = @_;

      WARNING("Shell Manager Writer Errror: $msg");
      $hdl->destroy;
    };

  return $hdl;
} 


my $shell_mgr_hdl;
sub init_shell_mgr {
  my ( $self , $cb) = @_;

  if ($shell_mgr_hdl) {
     $cb->() if $cb;
     return;
  }

  TRACE('Starting Shell Manager');

  # Init reader now that we should be done forking.
  $self->shell_mgr_reader();

  AnyEvent::Fork
    ->new
    ->require("App::RaffiWare::ExCollect::Worker")
    ->send_fh( $self->shell_mgr_from_parent, $self->shell_mgr_to_parent )
    ->send_arg( $self->cmd_dir )
    ->run("App::RaffiWare::ExCollect::Worker::shell_manager",
       sub {
         my ($fh) = @_; 

         TRACE('Started Shell Manager'); 

         $shell_mgr_hdl = new AnyEvent::Handle
           fh      => $fh,
           on_read => sub {
             my ($hdl) = @_;

             # Child process STDOUT sends log data.
             $hdl->unshift_read( json => sub {
                my ($hdl, $struct) = @_;
                TRACE('SHELL MGR OUT: '. encode_json($struct) );
 
                if ( my $level = $struct->{log} ) {
                  LOG( $level => $struct->{msg} );
                }
             });
           },
           on_eof => sub {
             TRACE("Shell Manager EOF");
             undef $shell_mgr_hdl;
           },
           on_error => sub {
             my ($hdl, $fatal, $msg) = @_;

             ERROR("Shell Manager Error - $msg");
             $hdl->destroy;
             undef $shell_mgr_hdl; 
           }; 

           $cb->() if $cb;
       });
}

sub fetch_jobs_timer {
  my ( $self, $ts ) = @_;

  my $last_ts   = $self->get_last_check('fetch_jobs');
  my $delta     = $ts - $last_ts;
  my @pad_range = (-30..30);
  my $interval  = $self->job_poll_interval + $pad_range[int(rand(@pad_range))];

  return if $delta < $interval; 

  $self->fetch_jobs();
  $self->set_last_check( fetch_jobs => $ts );
}

sub fork_worker  {
  my ( $self, @args ) = @_;

  my $cb = pop @args;

  AnyEvent::Fork
    ->new
    ->require( $self->worker_template_class )
    ->send_arg(@args)
    ->run("App::RaffiWare::ExCollect::Worker::run_fork", 
       sub {
         my ($fh) = @_; 

         my $fork_hdl; $fork_hdl = new AnyEvent::Handle
           fh      => $fh,
           on_read => sub {
             my ($hdl) = @_;

             $hdl->unshift_read( json => sub {
               my ($hdl, $struct) = @_;

               TRACE('Returned from '. Dumper(\@args));
               TRACE('Fork Data: '. encode_json($struct) );
 
               if ( my $level = $struct->{log} ) {
                 LOG( $level => $struct->{msg} );
               }

               if ( my $error = $struct->{error} ) {
                 ERROR("Worker returned error: $error");
               }

               $cb->($struct->{return}) if exists $struct->{return};
             });
           },
           on_eof => sub {

             TRACE('Fork Worker EOF');
             undef $fork_hdl;
           },
           on_error => sub {
             my ($hdl, $fatal, $msg) = @_;

             ERROR("Fork Worker Error - $msg");
             $hdl->destroy;
             undef $fork_hdl; 
           }; 

       });
} 

sub fetch_jobs  {
  my ( $self ) = @_;

  $self->fork_worker( 
    'fetch_jobs',
    cmd_dir   => $self->cmd_dir,
    cfg_file  => $self->cfg_file,
    log_level => $self->log_level,
    sub {
      my $return = shift;

      my $job_ids = try {

          local $SIG{__DIE__}; # Don't pollute logs
          decode_json($return);
        }
        catch {
          ERROR("Job Ids failed to decode: ". $return || '' );
          return;
        };

      $self->queue_job($_) for @{$job_ids || []};  
    }
  );

  #$self->worker_pool->(
  #  'fetch_jobs',
  #  cmd_dir  => $self->cmd_dir,
  #  cfg_file => $self->cfg_file,
  #  debug    => $self->debug,
  #  sub { 
  #    my $job_ids = shift;

  #    DEBUG("Fetch Jobs Worker returned: $job_ids"); 

  #    $job_ids = try { 
  #      decode_json($job_ids);
  #    }
  #    catch {
  #      ERROR("Job Ids failed to decode");  
  #      return;
  #    };

  #    $self->queue_job($_) for @{$job_ids || []};
  #  }
  #); 
}

sub replay_cache_timer {
  my ( $self, $ts  ) = @_;

  my $last_ts  = $self->get_last_check('replay_cache');
  my $delta    = $ts - $last_ts;
  my $interval = $self->replay_check_interval;

  return if $delta < $interval;

  $self->replay_cache();
  $self->set_last_check( replay_cache => $ts );
}

sub replay_cache {
  my ( $self, $ts, $now  ) = @_;

  TRACE("Checking for replay requests");

  $self->fork_worker(
    'replay_check',
    cmd_dir   => $self->cmd_dir,
    cfg_file  => $self->cfg_file,
    log_level => $self->log_level, 
    sub { TRACE("Replay Check Worker returned @_") }
  );

  #$self->worker_pool->(
  #  'replay_check',
  #  cmd_dir  => $self->cmd_dir,
  #  cfg_file => $self->cfg_file,
  #  debug    => $self->debug,
  #  sub { DEBUG("Replay Check Worker returned @_") }
  #); 
}

sub ws_ping_timer {
  my ( $self, $ts ) = @_;

  my $interval = $self->ws_client_ping_interval;
  my $last_ts  = $self->get_last_check('ws_ping');
  my $delta    = $ts - $last_ts;

  return if $delta < $interval; 

  TRACE('WS ping');
  $self->send_ws_msg({cmd => 'ping'}, 1);
  $self->set_last_check( ws_ping => $ts );
}

has 'ae_cv' => (
  is      => 'ro',
  isa     => InstanceOf ['AnyEvent::CondVar'],
  default => sub { AE::cv },
  handles => {
    start_event_loop => 'recv',
    end_event_loop   => 'send'
  }
); 

has 'worker_template_class' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_worker_template_class'
);

sub _build_worker_template_class {
  my ($self) = @_;

  return 'App::RaffiWare::ExCollect::Worker';
}

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

  return $self->worker_template
    ->AnyEvent::Fork::Pool::run(
       'App::RaffiWare::ExCollect::Worker::run',

        # pool management
        max        => $self->max_workers, # absolute maximum # of processes
        idle       => 0,                  # minimum # of idle processes
        load       => 1,                  # queue at most this number of jobs per process
        start      => 0.1,                # wait this many seconds before starting a new process
        stop       => 10,                 # wait this many seconds before stopping an idle process
        on_destroy => $self->ae_cv,       # called when object is destroyed
      );
}

sub shutdown {
  my ($self) = @_;

  $self->_clear_ws_client;
  $self->_clear_timer;
  $self->_clear_shell_mgr_reader;
  $self->_clear_shell_mgr_writer; 
  $self->_shutdown_pool;
  $self->end_event_loop;

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

=item --timer-check-interval=i  [30]

Time in seconds between checking for all interval evnnts.

=item --job-poll-interval=i    [60]

Time in seconds between checking for new jobs.

=item --ws-client-ping-interval=i [120]

Time in seconds between websocket keep-alive pings

=item --replay-check-interval=i   [120]

Time in seconds between checking the replay cache.

=item --max-workers=i  [2]

Maximum number of worker processes running jobs. 

=item --max-startup-delay=i [60]

Maximum number of seconds the random start up delay can be.

=back

=head1 CONFIGURATION

=over 4

=item timer_check_interval=i

Time in seconds between checking for all interval evnnts. 

=item job_poll_interval=i 

Time in seconds between checking for new jobs. 

=item ws_client_ping_interval=i

Time in seconds between websocket keep-alive pings 

=item replay_check_interval=i

Time in seconds between checking the replay cache. 

=item max_workers=i

Maximum number of worker processes running jobs.

=item max_startup_delay=i

Maximum number of seconds the random start up delay can be. 

=back 

=cut  

