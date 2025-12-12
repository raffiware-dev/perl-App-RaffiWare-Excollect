package App::RaffiWare::ExCollect::Worker;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |;

use AnyEvent;
use AnyEvent::Handle; 
use Cwd;
use Data::Dumper;
use File::HomeDir;
use POSIX ":sys_wait_h";
use Try::Tiny;

use App::RaffiWare::Logger; 

# Delay loading these to reduce memory usage 
# in AnyEvent::Fork::Pool manager process.
sub lazy_load_deps {

  require Crypt::PK::X25519;
  require Crypt::PK::Ed25519;
  require Crypt::RFC8188;
  Crypt::RFC8188->import( qw| ece_encrypt_aes128gcm ece_decrypt_aes128gcm |);
  require Crypt::KeyDerivation;
  Crypt::KeyDerivation->import( qw| hkdf |);
  require Unicode::Escape;
  require Proc::Daemon;
  require MIME::Base64;
  MIME::Base64->import(qw| encode_base64 decode_base64 encode_base64url decode_base64url |);
  require JSON;
  JSON->import(qw| encode_json |);
  require IO::Tty::Util;
  IO::Tty::Util->import( qw(forkpty) );
  require IO::Stty;  

}

with 'App::RaffiWare::Role::HasCfg',
     'App::RaffiWare::Role::HasLogger', 
     'App::RaffiWare::Role::HasAPIClient', 
     'App::RaffiWare::ExCollect::Role::HasJobs';

has '+api_class' => ( default => sub { 'App::RaffiWare::ExCollect::API' } ); 

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'keys' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_load_keys',
  handles => {
    get_user_key => 'get',
  }
); 

sub _load_keys {
  my $self = shift;

  my $key_file = sprintf( '%s/keys', $self->cmd_dir );

  return App::RaffiWare::Cfg->new( cfg_file => $key_file );
}
 
sub run_pool {

  # If we only want workers executing one job and 
  # then freeing up memory
  AnyEvent::Fork::Pool::retire()
    if defined &AnyEvent::Fork::Pool::retire; 

  run(@_);
}

sub run_fork {
  my ( $fh, @args ) = @_;

  my $data = try { 

    return { return => run(@args) };
  }
  catch {
    return { error => "$_" };
  };

  syswrite $fh, encode_json($data); 
}

sub run {
  my ( $work_type, @args ) = @_;

  lazy_load_deps();

  if ( $work_type eq 'job' ) {
    return run_job(@args);
  }
  elsif ( $work_type eq 'replay_check' ) {
    return run_replay(@args);
  }
  elsif ( $work_type eq 'fetch_jobs' ) {
    return fetch_jobs(@args);
  }
  elsif ( $work_type eq 'get_ws_token' ) {
    return get_exc_ws_token(@args);
  }
}

sub run_job {
  my ( $job_id, %wargs ) = @_; 

  my $worker = init_worker(%wargs); 

  my $job = $worker->load_job($job_id);

  return if !$job->lock();

  return if $job->get_job_val('status') ne 'queued'; 

  my $daemon = Proc::Daemon->new( 
    work_dir     => getcwd(), 
    pid_file     => $job->cmd_dir .'/jobs/'. $job->job_id .'.pid',
    child_STDOUT => '+>>'. $job->cmd_dir .'/jobs/'. $job->job_id .'/logs/log',
    child_STDERR => '+>>'. $job->cmd_dir .'/jobs/'. $job->job_id .'/logs/log.err'
  );

  # We create a daemon for the job to execute in so if the watcher process is killed
  # the job will finish executing. We still want to try and poll for when the daemon 
  # exits so we hold a spot in the worker pool while the job is running.
  my $pid = $daemon->Init() // die ('failed to daemonize');

  # In daemonized child
  unless ($pid) {

    $job->execute();
    $job->unlock(); 

    exit(0); 
  }

  # Wait for job daemon exit;
  sleep 2;

  while (my $status = $daemon->Status) { sleep 1 }

  return $job_id;
}

sub run_replay {
  my ( %wargs ) = @_;

  my $worker = init_worker(%wargs);

  $worker->api->run_replay_requests();
}

sub fetch_jobs {
  my ( %wargs ) = @_;

  my @delay_range = (0 .. 10);
  sleep $delay_range[int(rand(@delay_range))];

  my $worker = init_worker(%wargs);

  TRACE("Checking for new jobs");

  my $jobs_collection = $worker->api->get_jobs() or return 0; 

  my @new_jobs;
  foreach my $job ( @{$jobs_collection->{collection}} ) {

    if ( $worker->load_job( $job->{id} ) ) {
      WARNING( sprintf( 'Job %s already fetch', $job->{id} ) );
      next;
    }

    INFO( sprintf( "Got new job %s", $job->{id} ) );
    DEBUG( Dumper( $job ) );

    my $job = $worker->init_job( $job );

    push @new_jobs, $job->job_id;
  } 

  return encode_json(\@new_jobs);

}

sub get_exc_ws_token {
  my ( %wargs ) = @_;

  my $worker = init_worker(%wargs);

  TRACE("Fetching Websocket Token");

  return $worker->api->get_exc_ws_token();
}

sub init_worker {
  my ( %wargs ) = @_;

  my $log_level = delete $wargs{log_level};

  my $worker = __PACKAGE__->new(%wargs);

  $worker->set_level($log_level) if $log_level;  
  $worker->logger(); 

  return $worker;
}

my %USER_MAP           = ();
my $scrollback_buf_len = 8192; # TODO make tunable; 

sub shell_manager {
  my ($fh, $cmd_read, $cmd_write, $cmd_dir) = @_;

  lazy_load_deps(); 

  $cmd_write->autoflush(1);

  my $worker = init_worker( cmd_dir => $cmd_dir ); 
  my $cv     = AE::cv; 

  my $logger = sub {
    my ( $level, $data ) = @_;

    my $msg = try { 
      encode_json({ log => $level, msg => $data});
    }
    catch {
      encode_json({ log => 'error', msg => "Error Encoding Msg: '$data' \n\n $@"});
    };

    syswrite $fh, $msg;
  };

  $worker->api; # build API object before changing directory;
                # otherwise late loading dependencies can break.
  chdir File::HomeDir->my_home;

  my $hdl = new AnyEvent::Handle
     fh      => $cmd_read,
     on_read => sub {
       my ($hdl) = @_; 

       $hdl->unshift_read ( json  => sub {
         my ($hdl, $cmd_struct)  = @_;

         $worker->run_command( $cmd_struct, $cmd_write, $cv, $logger );
       }); 

     },
     on_eof => sub {

       $logger->( warning => "Command Socket EOF" ); 
       $cv->send
     },
     on_error => sub {
       my ($hdl, $fatal, $msg) = @_;

       $logger->( warning => "Command Socket Error: $msg\n" );
       $hdl->destroy;
       $cv->send;
     };

  $cv->recv;
}

sub run_command {
  my ( $worker, $cmd_struct, $cmd_write, $cv, $logger ) = @_;  

  if ( my $cmd = $worker->can('_cmd_'. $cmd_struct->{cmd}) ) {
    # protect shell manager worker from crashing.
    try   { $worker->$cmd($cmd_struct, $cmd_write, $cv, $logger) }
    catch { $logger->( error => "Command Error: $_\n" ) }; 
  }
}

sub _cmd_spawn_shell {
  my ( $worker, $cmd_struct, $cmd_write, $cv, $logger ) = @_;  

  my $ident = $cmd_struct->{ident};  

  $logger->( trace => 'spawn_shell command');
  # TODO timeout terminal process.
  my $user    = $cmd_struct->{user};
  my $exc_key = $worker->get_terminal_user_key($cmd_struct, $logger); 

  unless ($exc_key) {
    send_data( $cmd_write, $user, $ident,
      return => 'spawn_shell',
      error  => 'Terminal Access Denied'
    );

    return;
  }

  my ( $our_dh_pub, $our_dh_sig, $dh_secret ) = $worker->get_dh_key_data(
                                                  $cmd_struct, 
                                                  $exc_key, 
                                                  $logger );

  unless ($our_dh_pub) {
    send_data( $cmd_write, $user, $ident,
      return => 'spawn_shell',
      error  => 'Invalid Key'
    );

    return;
  }

  my $user_dat = $USER_MAP{$user} ||= { id => $user };
  my $client_key = $worker->cmd_cfg->get('key_data'); 

  $user_dat->{dh_secret} = $dh_secret;

  if ( $user_dat->{shell}) {

    $logger->( info => "Existing shell for $user");

    send_data( $cmd_write, $user, $ident,
      return   => 'spawn_shell', 
      data     => 'existing shell', 
      dh       => $our_dh_pub,
      dh_sig   => $our_dh_sig,
      key_data => $client_key
    );

    my $buff = $USER_MAP{$user}->{buffer};

    send_data( $cmd_write, $user, undef,
       cmd  => 'shell_out', 
       data => encrypt( $user_dat, $buff ) 
    ); 

    return 
  }

  $logger->( trace => 'creating shell' );

  my $params = $cmd_struct->{params};
  my $rows   = $params->{rows} || 40;
  my $cols   = $params->{cols} || 90;

  # Setup shell environment.
  local $ENV{EXC_USER} = $user;
  local $ENV{TERM}     = 'xterm-256color';

  my ($pid, $pty) = forkpty($rows, $cols, "/bin/bash", "-i") ;

  if ( !$pid ) {

    send_data( $cmd_write, $user, $ident,
      return => 'spawn_shell',
      error  => 'shell failed to spawn'
    );

    $logger->( error => "$user PTY failed to spawn" );

    return;
  }

  $logger->( trace => 'PTY setup' );

  $pty->autoflush(1);

  # Notify parent/user the shell successful spawned.
  send_data( $cmd_write, $user, $ident,
    return   => 'spawn_shell',
    data     => 'new shell spawned',
    dh       => $our_dh_pub,
    dh_sig   => $our_dh_sig,
    key_data => $client_key 
  );

  $logger->( trace => 'Setting up PTY handlers' ); 

  undef $user_dat->{buffer}; 
  $user_dat->{shell} = new AnyEvent::Handle
    fh      => $pty,
    on_read => sub {
      my ($hdl) = @_; 

      my $len = length $hdl->rbuf;

      $hdl->unshift_read( chunk => $len, sub {
        my $output = $_[1];
        $logger->( trace => "$user shell out: $output" ); 

        # Encode multi-byte characters as escaped Unicode code points 
        # so no one gets confused later.
        my $utf8_enc = Unicode::Escape::escape($output); 

        my $buffer = $user_dat->{buffer};
        # Limit the size of the scroll back buffer while appending latest output.
        $user_dat->{buffer} = substr( ( $buffer // ''). $utf8_enc, -$scrollback_buf_len );

        send_data( $cmd_write, $user, undef,
          cmd  => 'shell_out', 
          data => encrypt( $user_dat, $utf8_enc ) 
        );
      });

    },
    on_eof => sub {
      my ($hdl) = @_; 

      send_data( $cmd_write, $user, undef,
        shell_event => 'pty_error',
        data        => 'EOF'
      );

      $logger->( warning => "$user PTY EOF" );

      reaper();

      delete $USER_MAP{$user};
      $hdl->destroy;

      check_idle( \%USER_MAP, $logger, $cv );
    },
    on_error => sub {
      my ($hdl, $fatal, $msg) = @_;

      send_data( $cmd_write, $user, undef,
        shell_event => 'pty_error',
        data        => $msg
      ); 

      $logger->( error => "$user PTY Error: $msg" );

      reaper(); 

      delete $USER_MAP{$user}; 
      $hdl->destroy;

      check_idle( \%USER_MAP, $logger, $cv ); 
    }; 

  $worker->api->log_terminal_shell_spawn($user);

  $logger->( info => "Spawned shell for $user" );
}

sub check_idle {
  my ($user_map, $logger, $cv) = @_;

  return if keys %$user_map;

  $logger->( warning => 'Shutting down idle shell manager' ); 
  $cv->send();

}

sub reaper { 1 while waitpid(-1, WNOHANG) > 0;  }

sub _cmd_shell_in {
  my ( $worker, $cmd_struct, $cmd_write, $cv, $logger ) = @_;

  my $user = $cmd_struct->{user};
  my $data = $cmd_struct->{data};

  my $user_dat = $USER_MAP{$user} or return;

  my $pty_h  = $user_dat->{shell}; 
  my $pty_fh = $pty_h->fh;

  syswrite $pty_fh, decrypt( $user_dat, $data ); 
}

sub _cmd_shutdown {
  my ( $worker, $cmd_struct, $cmd_write, $cv, $logger ) = @_; 

  $logger->( warning => 'Got Shutdown' );
  $cv->send;
}

sub get_terminal_user_key {
  my ( $worker, $cmd_struct, $logger ) = @_;

  unless ( $cmd_struct->{key_id} ) {

    $logger->( error => "Missing  key id" ); 
    return;
  }

  my $user   = $cmd_struct->{user};
  my $key_id = $cmd_struct->{key_id};

  my $user_key_data = $worker->api->get_terminal_user_key( $user, $key_id );

  unless ($user_key_data) {

    $logger->( error => "$user $key_id key not found" );
    return
  }

  my $user_pub_key = $user_key_data->{public_key};

  return Crypt::PK::Ed25519->new(\decode_base64url($user_pub_key));
}

sub get_dh_key_data {
  my ( $worker, $cmd_struct, $exc_key, $logger ) = @_; 

  unless ( $cmd_struct->{dh} ) {

    $logger->( error => "Missing connection key" );
    return;
  }

  unless ( $cmd_struct->{dh_sig} ) {

    $logger->( error => "Missing connection key signature" );
    return;
  }

  my $user   = $cmd_struct->{user}; 
  my $dh_der = decode_base64url($cmd_struct->{dh});
  my $dh_sig = decode_base64url($cmd_struct->{dh_sig});

  unless ( $exc_key->verify_message( $dh_sig, $dh_der ) ) {

     $logger->( error => "$user DH Sig failed" ); 
     return; 
  }

  my $our_dh_key   = Crypt::PK::X25519->new()->generate_key;
  my $their_dh_key = Crypt::PK::X25519->new(\$dh_der);

  my $our_dh_sig = $worker->sign_dh_key($our_dh_key);
  my $our_dh_pub = encode_base64url($our_dh_key->export_key_der('public'));
  my $dh_secret  = $our_dh_key->shared_secret($their_dh_key);

  return (
    $our_dh_pub,
    $our_dh_sig,
    $dh_secret
  );
}

sub sign_dh_key {
  my ( $worker, $dh_key ) = @_;

  my $dh_pub   = $dh_key->export_key_der('public');
  my $priv_key = $worker->cmd_cfg->get('private_key');
  my $s_key    = Crypt::PK::Ed25519->new(\decode_base64url($priv_key));
  my $sig      = $s_key->sign_message($dh_pub);

  return encode_base64url($sig, '');
}

sub send_data {
  my ($fh, $user, $ident, %resp) = @_;

  my $json = encode_json({ 
    user   => $user, 
    $ident ? ( ident  => $ident ) : (),
    %resp
  });

  syswrite $fh, $json;
}

sub encrypt {
  my ( $user_dat, $plaintext ) = @_;

  # We do a few things here to stay interoperable with the javscript side
  # and its parameter requirements for the crypto functions we use.
  #
  # 1. http_ece javscript library only takes 128 bit IKM for AES128GCM encryption
  # so we run the ECDH secret through hkdf() to get properly sized and randomized
  # 128 bit IKM.
  #
  # 2. The empty string passed to hdkf() is the salt. ece_encrypt_aes128gcm() 
  # already uses a random salt that's automatically stored in each encrypted record 
  # header, no need to keep track of another just for resizing the IKM.
  my $secret        = $user_dat->{dh_secret};
  my $secret_128bit = hkdf( $secret, '', 'SHA256', 16, "Content-Encoding: aes128gcm\x00" );
  my $salt          = undef; # salt value is auto generated, no need to supply it
  my $cipher        = ece_encrypt_aes128gcm( $plaintext, $salt, $secret_128bit );

  return encode_base64url($cipher);
}

sub decrypt {
  my ( $user_dat, $ciphertext ) = @_;

  my $secret        = $user_dat->{dh_secret};
  my $secret_128bit = hkdf( $secret, '', 'SHA256', 16, "Content-Encoding: aes128gcm\x00" );
  my $cipher        = decode_base64url($ciphertext);

  return ece_decrypt_aes128gcm( $cipher, $secret_128bit );
}

1;
