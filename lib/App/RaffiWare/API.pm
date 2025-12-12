package App::RaffiWare::API;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use RaffiWare::APIUtils qw| 
  sign_exc_request 
  get_utc_timepiece 
  get_timestamp_iso8601 
  inflate_iso8601_timepiece 
  verify_exc_key_and_signer 
  verify_exc_response
|;

use App::RaffiWare::Logger;
use App::RaffiWare::ExCollect;

use Carp;
use Fcntl ':flock';
use HTTP::Request::Common;
use HTTP::Thin;
use HTTP::Request;
use JSON qw| decode_json encode_json |;
use Data::Dumper;
use Storable qw|store_fd fd_retrieve |;
use Time::HiRes;
use Try::Tiny;
use URI;

with 'MooX::Singleton', 
     'App::RaffiWare::Role::HasLogger', 
     'App::RaffiWare::Role::HasCfg';

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
);

has 'replay_dir' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  default => sub { sprintf( '%s/replay_cache', shift->cmd_dir ) }
);

has 'api_hostname' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  default => sub { shift->get_cfg_val('api_hostname') }
);

has 'timeout' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  default => sub { shift->get_cfg_val('api_timeout') }
);


has 'user_agent_name' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_user_agent_name'
); 

sub _build_user_agent_name {
  my $self = shift;

  return sprintf("Exc/v%s - %s",
                  $App::RaffiWare::ExCollect::VERSION,
                  $self->get_cfg_val('client_name') || '' )
}

has 'user_agent' => (
  is      => 'ro',
  isa     => InstanceOf ['HTTP::Thin'],
  lazy    => 1,
  builder => '_build_user_agent'
);

sub _build_user_agent { 
  my $self = shift; 

  return HTTP::Thin->new( 
    timeout    => $self->timeout,
    agent      => $self->user_agent_name,
    keep_alive => 0
  ); 
}

has 'last_api_time_offset_update' => (
  is      => 'rw',
  isa     => InstanceOf ['Time::Piece'],
  lazy    => 1,
  builder => '_build_last_api_time_offset_update',
  writer  => '_set_last_api_time_offset_update'
);

sub _build_last_api_time_offset_update {
  my $self = shift;

  return inflate_iso8601_timepiece( $self->get_cfg_val('last_api_time_offset_update') );
}

sub set_last_api_time_offset_update {
  my $self = shift;

  my $tp = get_utc_timepiece();

  $self->lock_cfg() or return;
  $self->set_cfg_val( last_api_time_offset_update => get_timestamp_iso8601($tp) );
  $self->unlock_cfg(); 

  $self->_set_last_api_time_offset_update($tp);
}

sub has_api_time_offset { shift->get_cfg_val('last_api_time_offset_update') ? 1 : 0 }

has 'api_time_offset' => (
  is      => 'rw',
  isa     => Num,
  lazy    => 1,
  writer  => '_set_api_time_offset',
  builder => '_build_api_time_offset',
);

sub _build_api_time_offset {
  my $self = shift;

  return ( $self->get_cfg_val('api_time_offset') || 0 );
}

sub set_api_time_offset {
  my ( $self, $offset ) = @_;


  $self->lock_cfg() or return; 
  $self->set_cfg_val( api_time_offset => $offset );
  $self->unlock_cfg();  

  $self->_set_api_time_offset($offset);

  $self->set_last_api_time_offset_update();
}

our $OFFSET_UPDATE_INT = 1 * 60 * 60; # 1 hour seconds

sub needs_api_time_offset_update {
  my ($self) = @_;

  return 1 if !$self->has_api_time_offset;

  my $last_dt = $self->last_api_time_offset_update();
  my $dt_now  = get_utc_timepiece();
  my $delta   = $dt_now - $last_dt;

  DEBUG("last offset update $last_dt $dt_now delta: $delta");

  return ( $delta > $OFFSET_UPDATE_INT );
}

sub update_api_time_offset {
  my ($self) = @_;

  return if $self->get_cfg_val('local_only'); 

  my $tp  = get_utc_timepiece();
  my $req = $self->_build_request(
    post => '/time_offset',
    body => { timestamp => get_timestamp_iso8601($tp) }
  );

  my $resp = $self->_do_request($req, retry => 3 );

  if ( !$resp->is_success ) {
    WARNING( "API time offset update failed: \n" . $resp->decoded_content );
    return undef;
  }

  my $offset = decode_json( $resp->decoded_content )->{message}->{offset};

  $self->set_api_time_offset($offset);

  return $offset;
}

has 'key_id' => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_key_id',
  writer    => '_set_key_id'
);

has 'private_key' => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_private_key',
  writer    => '_set_private_key'
);

sub has_key { $_[0]->has_key_id && $_[0]->has_private_key }

has 'keys' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_load_keys',
  handles => {
    is_key_cached => 'exists',
    _get_key      => 'get',
    add_key       => 'set',
    delete_key    => 'delete'
  }
);

sub _load_keys {
  my $self = shift;

  my $key_file = sprintf( '%s/keys', $self->cmd_dir );

  return App::RaffiWare::Cfg->new( cfg_file => $key_file, cfg_storage => 'json' );
} 

has '_revoked_keys' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_load_revoked_keys',
  handles => {
    is_revoked_key    => 'get',
    _add_revoked_keys => 'set',
    revoked_keys      => 'data'
  }
);

sub add_revoked_keys {
  my ($self, @key_ids) = @_; 

  $self->delete_keys(@key_ids);
  $self->_add_revoked_keys( map { ( $_ => 1 ) } @key_ids );
}

sub _load_revoked_keys {
  my $self = shift;

  my $key_file = sprintf( '%s/revoked_keys', $self->cmd_dir );

  return App::RaffiWare::Cfg->new( cfg_file => $key_file, cfg_storage => 'json' );
}

sub build_api_args {
  my ( $class, $cmd ) = @_;

  return +{};
}

sub request {
  my ( $self, $method, $path, %args ) = @_;

  return if $self->get_cfg_val('local_only');

  my $req = $self->_build_request( $method, $path, %args );

  return $self->_do_request( $req, %args );
}

sub signed_request {
  my ( $self, $method, $path, %args ) = @_;

  return if $self->get_cfg_val('local_only');

  if ( !$self->has_key ) {
    WARNING('No credentials configured');
    return;
  }

  my $req = $self->_build_request( $method, $path, %args );

  return $self->_do_request( $req, %args, sign_request => 1 );
}

sub _build_request {
  my ( $self, $method, $path, %args ) = @_;

  my $body    = $args{body};
  my $params  = $args{params};
  my $headers = $args{headers} || {};

  my $uri = URI->new( $self->api_hostname . $path );

  $uri->query_form(%$params) if $params;


  my @req_args = ( $uri, %$headers, 'user-agent' => $self->user_agent_name );

  if ($body) {
    push @req_args,
         ( 'Content-type' => 'application/json;charset=utf-8', 
           'Content'      => encode_json($body) )
  }

  my $map = {
    head   => \&HEAD,
    get    => \&GET,
    post   => \&POST,
    put    => \&PUT,
    patch  => \&PATCH,
    delete => \&DELETE
  };

  return $map->{ lc($method) }->(@req_args);
}

sub _do_request {
  my ( $self, $req, %args ) = @_;
    
  my $retry           = $args{retry} // 1;
  my $replayable      = $args{replayable} || 0;
  my $sign            = $args{sign_request};
  my $skip_verify     = $args{skip_verify_response}; 
  my %expected_errors = ( map { ( $_ => 1 ) } @{ $args{expected_errors} || [] } );

  if ($sign) {

    $self->update_api_time_offset()
      if $self->needs_api_time_offset_update;

    sign_exc_request( $self->key_id, $req, $self->private_key, $self->api_time_offset );
  }

  DEBUG( 'Request - '. Dumper($req) );
  # If we have a replayable request and pending requests to replay,
  # save the current request for replay and attempt to replay pending
  # requests first. This is to make sure updates are made in order.
  if ( $args{replayable} && $self->get_next_replay ) {

    WARNING("Found requests in replay-cahce");
    $self->freeze_request( $req, %args );

    # Note this may fail sometimes since other workers running requests might
    # have already locked the replay cache.
    try {
      $self->run_replay_requests();
    };

    return;
  }

  my $resp = try { local $SIG{__DIE__}; $self->user_agent->request($req) };

  DEBUG('Response - '. Dumper($resp) );

  while ( !$resp->is_success && !$expected_errors{ $resp->code } ) {

    my $err       = $self->get_error($resp);
    my $retriable = $self->is_retriable($resp);

    ERROR( sprintf( 'API ERROR %i : %s', $err->{error_type_id}, $err->{error} ) );

    if ( $replayable and !$retry and $retriable ) {
      $self->freeze_request( $req, %args );
    }

    last if !$retry or !$retriable;

    $retry--;

    sleep 5;

    # re-sign request so it isn't expired.
    ($req) = sign_exc_request( $self->key_id, $req, $self->private_key, $self->api_time_offset )
      if ($sign);

    $resp = try { local $SIG{__DIE__}; $self->user_agent->request($req) };
  }

  my $ret = try {

    $resp->request($req);

    # $skip_verify should only be set for the request 
    # that fetches the root authority data.
    #
    # We also skip on 599 timeout/could not connect
    # since we wont have a response to verify
    unless ( $skip_verify or $resp->code == 599 ) {

       my $authority = $self->get_cfg_val('root_authority')->{public_key};
       verify_exc_response($resp, $authority) or die('Bad Signature');
    }
  }
  catch {
    ERROR("Response verification failed: $_"); 

    return undef;
  }; 

  return $resp;
}

sub is_retriable {
  my ( $self, $resp ) = @_;

  my $code_type = substr( $resp->code, 0, 1 );
  my $err       = $self->get_error($resp);

  return 1 if $code_type == 5;

  return 1 if $err->{error_type_id} == 4012;    # Expired.

  return 0;
}

sub run_replay_requests {
  my ($self) = @_;

  return 0 if !-d $self->replay_dir;

  open my $lock_fh, '>', $self->replay_dir . '/.lock' 
    or FATAL("Cannot open replay lock file: $!");

  if ( !flock( $lock_fh, LOCK_EX | LOCK_NB ) ) {
    WARNING("Unable to lock replay-dir: $!");
    close $lock_fh;
    return 0;
  }

  while ( my $replay_file = $self->get_next_replay() ) {
    my $ret = $self->replay_request($replay_file);

    # Requests are still failing.
    last if !$ret;

    sleep int( rand(3) ) + 1;
  }

  close $lock_fh;

  return 1;
}

sub get_next_replay {
  my ($self) = @_;

  return if !-d $self->replay_dir;

  opendir my $dir, $self->replay_dir or FATAL("Cannot open replay directory: $!");

  my @files = sort { $a <=> $b } grep { /^[0-9]+\.[0-9]+$/ } readdir $dir;

  closedir $dir;

  return $files[0];
}

sub replay_request {
  my ( $self, $replay_file ) = @_;

  my $file = sprintf( '%s/%s', $self->replay_dir, $replay_file );

  open my $fd, '<', $file or FATAL("Unable to open replay-cache file: $!");
  binmode $fd;

  my $replay = fd_retrieve($fd);

  close $fd;

  my ( $req, $args ) = @$replay;

  my $resp = $self->_do_request( $req, %$args, replayable => 0 );

  my %expected_errors = ( map { ( $_ => 1 ) } @{ $args->{expected_errors} || [] } );

  if ( $resp and $resp->is_success || $expected_errors{ $resp->code } ) {
    unlink $file;
    return 1;
  }
  else {
    WARNING("Replay of $replay_file failed");
    return 0;
  }
}

sub freeze_request {
  my ( $self, $req, %args ) = @_;

  mkdir $self->replay_dir if !-d $self->replay_dir;

  my $time = Time::HiRes::time();
  my $file = sprintf( '%s/%s', $self->replay_dir, $time );

  open my $fd, '>', $file or FATAL("Unable to open replay-cache file: $!");
  binmode $fd;

  store_fd( [ $req, \%args ], $fd ) or FATAL("store_fd: $!\n");

  close $fd;
}

sub get_error {
  my ( $self, $resp ) = @_;

  return if $resp->is_success;

  if ( $resp->header('content-type') eq 'application/json' ) {

    my $json = decode_json( $resp->decoded_content );

    return { error => $json->{error}, error_type_id => $json->{error_type_id} };
  }
  else {
    return { error => $resp->content, error_type_id => $resp->code };
  }
}

sub get_error_str {
  my ( $self, $resp ) = @_;

  my $err = $self->get_error($resp) or return;

  return sprintf( '%s - %s', $err->{error_type_id}, $err->{error} );
}

sub get_message {
  my ( $self, $resp ) = @_;

  return if !$resp->is_success;

  my $json = decode_json( $resp->decoded_content );

  return $json->{message};
}

sub api_datetime {
  my ($self) = @_;

  my $offset          = $self->api_time_offset;
  my ($cur_dt, $frac) = get_utc_timepiece();

  return $cur_dt + $offset;
}

sub api_time_stamp { return get_timestamp_iso8601( shift->api_datetime ) }

sub fetch_authority_key {
  my ( $self, $activation_token ) = @_;

  my $resp = $self->request( 
    get                  => "/authority",
    skip_verify_response => 1  
  );

  if ( !$resp->is_success ) {
     ERROR('Could not fetch authority key');
     return;
  }

  my $msg = $self->get_message($resp);

  $self->set_cfg_val( root_authority => $msg );
}

sub get_key {
  my ( $self, $key_id, $endpoint ) = @_;

  croak("No Key Id") if !$key_id;
  croak("No Endpoint") if !$endpoint; 

  my $key_data = $self->_get_key($key_id);

  if ( !$key_data ) {
    my $resp = $self->signed_request( 
      get    => $self->uri_base . $endpoint,
      params => { id => $key_id }
    );

    if ( $resp && !$resp->is_success ) {
      ERROR( "Failed to fetch key from endpoint - ". $self->get_error_str($resp) );
      return;
    }

    $key_data = $self->get_message($resp);

    $self->add_key( $key_id, $key_data );
  }

  # Check for expired/revoked key.
  if ( !try { $self->verify_key($key_data) } ) {
    ERROR( "$key_id - Key Verification Failed" );
    return; 
  }

  return $key_data; 
}

sub verify_key {
  my ( $self, $key_data ) = @_; 

  my $id = $key_data->{id} || '';

  my $ret = try {

    my $authority = $self->get_cfg_val('root_authority')->{public_key};
    my $revoked   = $self->revoked_keys();

    verify_exc_key_and_signer( $key_data, $authority, $revoked );
  }
  catch {
    # die here ?
    ERROR("Key $id Verification Error: $_"); 

    return 0;
  };

  return $ret;
}

1;
