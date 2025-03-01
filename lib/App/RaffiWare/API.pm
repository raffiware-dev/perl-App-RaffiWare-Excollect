package App::RaffiWare::API;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use RaffiWare::APIUtils qw| sign_exc_request get_utc_time_stamp get_utc_datetime
                            get_timestamp_iso8601 inflate_iso8601_datetime |;

use App::RaffiWare::Logger;

use Fcntl ':flock';
use HTTP::Request::Common;
use HTTP::Thin;
use HTTP::Request;
use JSON qw| decode_json encode_json |;
use DateTime;
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
  default => sub { shift->get_cfg_val('api_hostname') || 'https://devapi.raffiware.io' }
);

has 'timeout' => (
  is      => 'ro',
  isa     => Int,
  lazy    => 1,
  default => sub { shift->get_cfg_val('api_timeout') || 15 }
);

has 'user_agent' => (
  is      => 'ro',
  isa     => InstanceOf ['HTTP::Thin'],
  lazy    => 1,
  builder => '_build_user_agent'
);

sub _build_user_agent { my $self = shift; HTTP::Thin->new( timeout => $self->timeout ) }

has 'last_api_time_offset_update' => (
  is      => 'rw',
  isa     => InstanceOf ['DateTime'],
  lazy    => 1,
  builder => '_build_last_api_time_offset_update',
  writer  => '_set_last_api_time_offset_update'
);

sub _build_last_api_time_offset_update {
  my $self = shift;

  return inflate_iso8601_datetime( $self->get_cfg_val('last_api_time_offset_update') );
}

sub set_last_api_time_offset_update {
  my $self = shift;

  my $dt = get_utc_datetime();

  $self->set_cfg_val( last_api_time_offset_update => get_timestamp_iso8601($dt) );
  $self->_set_last_api_time_offset_update($dt);
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

  $self->set_last_api_time_offset_update();
  $self->set_cfg_val( api_time_offset => $offset );
  $self->_set_api_time_offset($offset);
}

our $OFFSET_UPDATE_INT = 1 * 60 * 60; # 1 hours seconds

sub needs_api_time_offset_update {
  my ($self) = @_;

  return 1 if !$self->has_api_time_offset;

  my $last_dt = $self->last_api_time_offset_update();
  my $dt_now  = get_utc_datetime();
  my $delta   = $dt_now->subtract_datetime_absolute($last_dt)->seconds;

  DEBUG("offset update $last_dt $dt_now delta: $delta");

  return ( $delta > $OFFSET_UPDATE_INT );
}

sub update_api_time_offset {
  my ($self) = @_;

  my $dt  = get_utc_datetime();
  my $req = $self->_build_request(
                     POST => '/time_offset',
                     body => { timestamp => get_timestamp_iso8601($dt) }
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

  my @req_args = ( $uri, %$headers );

  push @req_args, ( 'Content-type' => 'application/json;charset=utf-8', 'Content' => encode_json($body) )
    if $body;

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
  my %expected_errors = ( map { ( $_ => 1 ) } @{ $args{expected_errors} || [] } );

  if ($sign) {

    $self->update_api_time_offset()
      if $self->needs_api_time_offset_update;

    my $tokens;
    ( $req, $tokens ) = sign_exc_request( $self->key_id, $req, $self->private_key, $self->api_time_offset );

    DEBUG( Dumper($tokens) );
    DEBUG( Dumper($req) );
  }

  # If we have a replayable request and pending requests to replay,
  # save the current request for replay and attempt to replay pending
  # requests first. This is to make sure updates are made in order.
  if ( $args{replayable} && $self->get_next_replay ) {

    INFO("Found requests in replay-cahce");
    $self->freeze_request( $req, %args );

    # Note this may fail often since other workers running requests might
    # have already locked the replay cache.
    try {
      $self->run_replay_requests();
    }

    return;
  }

  my $resp = do { local $SIG{__DIE__}; $self->user_agent->request($req) };

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

    $resp = do { local $SIG{__DIE__}; $self->user_agent->request($req) };
  }

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

  return if !-d $self->replay_dir;

  open my $lock_fh, '>', $self->replay_dir . '/.lock' or FATAL("Cannot open replay lock file: $!");

  if ( !flock( $lock_fh, LOCK_EX | LOCK_NB ) ) {
    WARNING("Unable to lock replay-dir: $!");
    close $lock_fh;
    return;
  }

  while ( my $replay_file = $self->get_next_replay() ) {
    my $ret = $self->replay_request($replay_file);

    # Requests are still failing.
    last if !$ret;

    sleep int( rand(3) ) + 1;
  }

  close $lock_fh;
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

  my $offset = $self->api_time_offset;
  my $cur_dt = get_utc_datetime();

  return $cur_dt->subtract( seconds => $offset ); 
}

sub api_time_stamp { return get_timestamp_iso8601( shift->api_datetime ) }

1;
