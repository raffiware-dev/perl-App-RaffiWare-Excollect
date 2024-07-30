package App::RaffiWare::ExCollect::Job;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |; 

use RaffiWare::APIUtils qw| verify_exc_tokens gen_random_string msg_from_tokens|;

use Carp;
use Cwd qw| abs_path |;
use Data::Dumper;
use Errno qw( EAGAIN  );
use English qw( -no_match_vars ) ;
use Fcntl; 
use File::Copy;
use JSON qw| encode_json |;
use POSIX;
use Digest::SHA qw|sha256_hex|;  
use Text::ParseWords;
use Text::Template::Simple;
use Try::Tiny;

use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;  
use App::RaffiWare::ExCollect::Job::Logger;

with 'App::RaffiWare::Role::HasLogger',
     'App::RaffiWare::Role::HasAPIClient',
     'App::RaffiWare::ExCollect::Role::HasHostData'; 

has '+api_class' => (
  default => sub {'App::RaffiWare::ExCollect::API'}
); 

has 'archived' => (
  is       => 'ro',
  isa      => Bool,
  default  => 0
);

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'job_id' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'job_dir' => (
  is       => 'ro',
  isa      => Str,
  lazy     => 1,
  clearer => '_clear_job_dir',
  builder => '_build_job_dir'
); 

sub _build_job_dir {
  my ($self) = @_; 

  if ( $self->archived ) {
      return $self->archive_dir
  }

  return sprintf('%s/jobs/%s', $self->cmd_dir, $self->job_id);
}

has 'archive_dir' => (
  is       => 'ro',
  isa      => Str,
  lazy     => 1,
  builder => '_build_archive_dir'
); 

sub _build_archive_dir {
  my ($self) = @_; 

  return sprintf('%s/archive/%s', $self->cmd_dir, $self->job_id);
}  

has 'job_state' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_load_job_state',
  writer  => '_set_job_state',
  handles => {
    get_job_val => 'get',
    set_job_val => 'set',
    lock        => 'lock',
    unlock      => 'unlock'
  }
); 

sub _load_job_state {
  my $self = shift; 

  my $state_file = sprintf('%s/state', $self->job_dir ); 

  return App::RaffiWare::Cfg->new( cfg_file => $state_file );  
}

sub reload_job_state {
  my $self = shift; 

  return $self->_set_job_state($self->_load_job_state($self->job_id)); 
} 

has 'job_logger' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::ExCollect::Job::Logger'],
  lazy    => 1,
  builder => '_build_job_logger',
  clearer => '_clear_job_logger',
  handles => {
    log_job_message => 'log_message'
  }
); 

sub _build_job_logger { 
   my $self = shift;

   my $log_level = $self->get_job_val('log_level') || 'info';  

   return App::RaffiWare::ExCollect::Job::Logger->new( 
               job_id  => $self->job_id, 
               job_dir => $self->job_dir,
               api     => $self->api,
               cmd_cfg => $self->cmd_cfg,
               level   => $log_level );
}  

has 'stdout_handler' => (
  is      => 'ro',
  isa     => CodeRef,
  lazy    => 1, 
  builder => '_build_stdout_handler'
); 

sub _build_stdout_handler {
  my $self = shift;

  my $job_id = $self->job_id;

  return sub {
      my $data = shift;

      $self->log_job_message('stdout', $data );
  };
}

has 'stderr_handler' => (
  is      => 'ro',
  isa     => CodeRef,
  lazy    => 1, 
  builder => '_build_stderr_handler'
); 

sub _build_stderr_handler {
  my $self = shift;

  my $job_id = $self->job_id; 

  return sub {
      my $data = shift;

      $self->log_job_message('stderr', $data ); 
  };
} 

has 'final_tts' => (
  is       => 'ro',
  isa      => InstanceOf['Text::Template::Simple'],
  lazy     => 1,
  builder  => '_build_final_tts'
); 

my $HOSTV_START = '#CV-';
my $HOSTV_END   = '-CV#'; 

sub _build_final_tts {
    my ($self) = @_; 

    return Text::Template::Simple->new( 
              delimiters => [ 
                $HOSTV_START,
                $HOSTV_END  
              ] 
           );
}  

has 'final_command_bin' => (
  is       => 'ro',
  isa      => Str,
  writer   => '_set_final_command_bin'
); 

has 'final_command_args' => (
  is       => 'ro',
  isa      => ArrayRef,
  writer   => '_set_final_command_args'
); 

has 'final_command_string' => (
  is       => 'ro',
  isa      => Str,
  lazy     => 1,
  builder => '_build_final_command_string'
); 

sub _build_final_command_string {
  my $self = shift; 

  my $client_name = $self->get_job_val('client_name');
  my $string      = $self->get_job_val('command_string');
  my $instance    = $self->get_job_val('instance'); 
  my $type        = $instance->{execute_type}; 

  my @hostvs = $string =~ /\Q${HOSTV_START}\E(.+?)\Q$HOSTV_END\E/g; 

  if (@hostvs) {

    my %extra_vars = ( ClientName => $client_name );

    $string = $self->final_tts->compile(
                       $string .' ', # Ensure string is not inferred to be file path.
                       [
                         map {
                           ( $_ => $extra_vars{$_} // $self->get_host_data_val($_) // 'UNDEFINED' ) 
                         } @hostvs,
                       ],
                       {
                          map_keys => 1
                       });
     chop($string); 
  }

  if ( $type eq 'script' ) {

       my $bin     = sprintf('%s/script.PL', abs_path($self->job_dir) );
       my $source  = $instance->{script_src} or die('No script source');

       open my $bin_fh, '>', $bin or die('Failed to create script bin file');
       print $bin_fh $source;
       close $bin_fh;

       chmod 0755, $bin;

       $string = "$bin $string";
  }

  return $string;
}


sub init {
  my ( $class, $job_cfg, %args ) = @_;

  my $job = $class->new( job_id => $job_cfg->{id}, %args); 

  if (!-d $job->job_dir) {  
      mkdir $job->job_dir;
      mkdir $job->job_dir .'/logs'; 
  }

  $job->set_job_val( %$job_cfg{qw| id status command_string priority archived command instance 
                                   client_name  |} );

  return $job;  
}


sub execute {
  my ( $self ) = @_;  

  my $job_id = $self->job_id;

  # Fork so any errors setting up job execution don't kill 
  # the parent worker process..
  if ( my $pid = $self->_fork() ) {

     waitpid( $pid, 0 );

     $self->reload_job_state();

     return;
  } 

  $self->lock() or $self->watcher_exit(0, "Could not get lock");
  $self->reload_job_state(); 

  my $status = $self->get_job_val('status');

  if ( $status ne 'queued' ) {
      $self->watcher_exit(1, "Cannot execute command with status: $status"); 
  }

  if ( !$self->verify_command_signature() )  {
      $self->set_job_val( status => 'error' );
      $self->log_job_message('error', "Command Instance signature validation failed"); 
      $self->api->update_job( $job_id, { status => 'error' } );

      $self->watcher_exit(1, "Command Instance signature validation failed");
  }

  # TODO check if we are passed the start_time;


  # TODO 
  #if ( $status ne 'queued' ) { 
  #        # if running check pid   $exists = kill 0, $pid;
  #        # if complete or error update job status
  #  $self->api->update_job( $job_id, { status => 'complete' } ); 
  #}

  INFO("Starting job $job_id");
  
  # create script here if needed

  my $final_command = $self->final_command_string();
  DEBUG("Final command $final_command");

  my ($final_bin, @final_args) = shellwords($final_command);

  $self->_set_final_command_bin($final_bin); 
  $self->_set_final_command_args(\@final_args); 

  # Don't exit here on error once replay is implemented.
  $self->set_status('running', final_command_string => $final_command ) or $self->watcher_exit(0, "API status update failed");
  $self->set_job_val( pid => $PID );

  umask 0027; # rwx-rw----

  my ( $from_child, $to_parent )         = $self->setup_pipe();
  my ( $from_child_err, $to_parent_err ) = $self->setup_pipe(); 
  
  my $job_dir   = $self->job_dir(); 
  my $stdin_buf = sprintf('%s/stdin', $job_dir);  

  open my $from_parent, '<', $stdin_buf or $self->watcher_exit(101, "$stdin_buf error: $!")
    if -f $stdin_buf;

  # Parent becomes exec watcher processing data 
  # sent through the stdout and stderr pipes.
  if ( my $pid = $self->_fork() ) {

    # TODO eval alarm timeout

    $PROGRAM_NAME = 'exc: '. $job_id; 

    close $to_parent;
    close $to_parent_err;
    close $from_parent if -f $stdin_buf;
  
    my $pipes = [

       # TODO Queue up some output before sending?
       [ $from_child, $self->stdout_handler() ], 

       # Errors send right away
       [ $from_child_err, $self->stderr_handler() ]
    ];
  
    $self->watch_pipes($pipes);
  
    waitpid( $pid, 0 );

    my $child_exit = $CHILD_ERROR >> 8;
    my $status     = $child_exit ? 'error' : 'complete';

    $self->log_job_message('warning', "Exec exit $child_exit") if $child_exit; 
    $self->set_status($status);
    $self->set_job_val( exit => $child_exit ); 


    #$self->api->update_job( $job_id, { status => $status } ); 

    INFO("Finished job $job_id with status $status"); 

    $self->unlock();
    $self->watcher_exit(0, "Watcher completed"); 
  }
  else {

    close $from_child;
    close $from_child_err;


    # Reopen standard file handles to get/send from our
    # pipes;
    if ( -f $stdin_buf ) {
      open STDIN, "<&=" . fileno $from_parent
        or croak "$! redirecting STDIN";
    }

    open STDOUT, ">&=" . fileno $to_parent
      or croak "$! redirecting STDOUT";

    open STDERR, ">&=" . fileno $to_parent_err
      or croak "$! redirecting STDERR"; 

    my $command_bin = $self->final_command_bin;
    my $args        = $self->final_command_args;

    my $exec_args = [ $command_bin, @$args ];

    exec { $exec_args->[0] } @$exec_args;

    die "Exec failed\n";
  }

}

sub setup_pipe {

  pipe( my $r, my $w );

  # Get the current flags
  my $flags = 0; 
  fcntl( $r, F_GETFL, $flags) or die $!;

  # Add non-blocking to the flags
  $flags |= O_NONBLOCK; 
  fcntl( $r, F_SETFL, $flags) or die $!;

  # Auto flush writer
  my $old_fh = select($w);
  $| = 1;
  select($old_fh); 

  return ( $r, $w );
}

sub watch_pipes {
  my ( $self, $pipes ) = @_;

  my $rin          = '';
  my $handles      = {};

  foreach (@$pipes) {
     my $fh = $_->[0];
     my $fn = fileno($fh);

     vec($rin, $fn, 1) = 1; 
     $handles->{$fn} = $_
  }
  
  my $delay = 1 + rand();
  my $count = 1;
  sleep $delay;

  while ( 
    my @fns = keys %$handles
    and defined select( my $rout=$rin, undef, undef, 1 ) 
  ) { 
  
    for my $fn ( @fns ) {
      $self->poll_handle( $handles, $fn ) or vec($rin, $fn, 1) = 0 ;
    }

    if ( keys %$handles ) {
       # Exponential backoff for polling so we don't
       # hammer the API on long running commands.
       # A random portion of the previous delay is added to 
       # help prevent stampeding from multiple hosts running the 
       # same command..
       # We also set an upper bound on $count, which should
       # limit the delay to a value between some where between 
       # 70 and 100 seconds ..ish. This does mean we lose some
       # fidelity on the time of output.
       #
       $delay = int(2**$count++ * ($delay * rand()) ) if $count < 6;
       sleep $delay;
    }
  
  } 

}

sub poll_handle {
  my ( $self, $handles, $fn ) = @_;

  my $fh = $handles->{$fn}->[0];
  my $cb = $handles->{$fn}->[1];  
  my $rv;
  my $line = ''; 

  while ( $rv = sysread( $fh, my $bytes, 2048 ) ) {
    $line .= $bytes;
  } 

  my $read_error = $!;

  $cb->($line) if $line;

  if ( !$rv and $read_error != EAGAIN ) {
    delete $handles->{ $fn }; 
    close $fh;
    return undef;
  }

  return 1;
}

sub _fork {
  my $self = shift;

  my $job_id = $self->job_id;
  my $pid    = fork(); 

  FATAL("Failed fork in $job_id: $!") if !defined $pid;
 
  return $pid;
}

sub watcher_exit {
  my ($self, $exit_code, $msg ) = @_;

  my $full_msg =  sprintf('%s exit: %i - %s', $self->job_id, $exit_code, $msg );

  if ($exit_code) {
    WARNING($full_msg);
  }
  else {
    DEBUG($full_msg); 
  }

  exit($exit_code);
}

sub set_status {
  my ($self, $status, %opt_updates) = @_;

  # Send host data here if set.
  my $resp = $self->api->update_job( $self->job_id, { status => $status, %opt_updates } );

  # remove when replay implemented.or don't worry about it, 
  # only final status update really matters? status transition 
  # limits should also protect in cases where final update
  # succeeds and replay happens after.
  #
  if ($resp && !$resp->is_success) {
      return 
  } 

  $self->set_job_val( status => $status ); 

  return 1;
}

sub verify_command_signature {
  my ($self) = @_; 


  my $job_id   = $self->job_id;
  my $instance = $self->get_job_val('instance');
  my $command  = $self->get_job_val('command'); 

  my $pub_key_data = $self->api->get_command_user_key($job_id, $instance->{'signed_by'});

  if (!$pub_key_data) {
    ERROR("$job_id - Failed to get signed_by user public key");
    return 0;
  }

  my $tokens = { 
     instance_id    => $instance->{id},
     command_id     => $command->{id},
     site_id        => $instance->{'site'}, 
     site_user_id   => $instance->{'signed_by'},
     created_ts     => $instance->{'created_datetime'},
     key_id         => $pub_key_data->{key_id},
     command_string => $instance->{'command_string'},
  }; 

  my $type = $instance->{execute_type};

  if ( $type eq 'script' ) {
      $tokens->{command_string} .= sha256_hex($instance->{script_src});
  }

  DEBUG('TOKENS '. msg_from_tokens($tokens));

  my $pub_key_string = $pub_key_data->{public_key};

  return verify_exc_tokens( $tokens, $instance->{'site_user_signature'}, $pub_key_string );
} 

sub archive {
  my $self = shift; 

  $self->set_job_val( archived => 1 );
  $self->_clear_job_dir();
  $self->_clear_job_logger();
  $self->reload_job_state();

  move($self->job_dir, $self->archive_dir); 
}


1;
