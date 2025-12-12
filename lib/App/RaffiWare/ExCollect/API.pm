package App::RaffiWare::ExCollect::API;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use RaffiWare::APIUtils qw| 
  get_utc_timepiece 
  get_timestamp_iso8601 
  get_dh_encryptor 
  load_public_key 
  unprefix_uuid 
|;

use App::RaffiWare::Logger;
use App::RaffiWare::Cfg;

use HTTP::Request::Common;
use HTTP::Thin;
use HTTP::Request;
use JSON qw| decode_json encode_json |;
use Data::Dumper;
use URI;
use Try::Tiny;

use AnyEvent::WebSocket::Client;

extends 'App::RaffiWare::API';

sub build_api_args {
  my ( $class, $cmd ) = @_;

  return +{ cmd_dir => $cmd->cmd_dir };
} 

has 'client_id' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  default => sub { shift->get_cfg_val('client_id') }
); 

has 'site_id' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  default => sub { shift->get_cfg_val('site_id') }
);

has 'site_uuid' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  default => sub { unprefix_uuid( shift->site_id ) }
); 

has 'uri_base' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_uri_base'
);

sub _build_uri_base {
  my $self = shift;

  return sprintf( "/excollect_api/clients/%s", $self->client_id );
}

sub get_exc_ws_token {
  my $self = shift; 

  if ( my $token = $self->get_cfg_val('exc_ws_token') ) {

    return $token;
  }
  else {

    my $resp = $self->signed_request( get => $self->uri_base .'/get_websocket_token');

    return '' if !$resp or !$resp->is_success;

    my $token = $self->get_message($resp)->{token};

    $self->lock_cfg() or return;  
    $self->set_cfg_val( exc_ws_token => $token );
    $self->unlock_cfg();   

    return $token;
  }

}

with 'App::RaffiWare::ExCollect::Role::HasClientData';

sub get_dh_key {
  my ( $self, $skip_verify ) = @_;

  my $resp = $self->request( get => "/excollect_api/clients/get_dh_key" );

  FATAL('Unable to fetch DH Key') if !$resp->is_success;

  my $their_key_data = $self->get_message($resp);

  if ( !try { $self->verify_key($their_key_data) } ) { 
    FATAL("DH Key verification failed") 
  }

  return ( load_public_key($their_key_data->{public_key}, 'X25519'), $their_key_data );
}

sub log_terminal_shell_spawn {
  my ( $self, $user ) = @_;

  return $self->signed_request( 
     post => $self->uri_base ."/terminal_login_event",
     body => {
        user => $user
     },
     replayable => 1 
  );
}

sub get_user_key {
  my ( $self, $user_id, $key_id ) = @_;

  my $endpoint = "/all_users/$user_id/public_key";

  return $self->_get_user_key( $user_id, $key_id, $endpoint )
}

sub get_terminal_user_key {
  my ( $self, $user_id, $key_id ) = @_;

  my $endpoint = "/terminal_users/$user_id/public_key";

  return $self->_get_user_key( $user_id, $key_id, $endpoint )
} 

sub get_command_user_key {
  my ( $self, $job_id, $user_id, $key_id ) = @_;

  my $endpoint = "/jobs/$job_id/command_instance/command/all_users/$user_id/public_key";

  return $self->_get_user_key( $user_id, $key_id, $endpoint );
}

sub _get_user_key {
  my ( $self, $user_id, $key_id, $endpoint ) = @_; 

  my $key_data = $self->get_key( $key_id, $endpoint ) or return;

  my $ctx_site = $key_data->{context}->{site};

  if ( $ctx_site ne $self->site_uuid ) {

    ERROR( "$key_id - Site Mismatch $ctx_site != ". $self->site_uuid );
    return; 
  } 

  my $ctx_user = $key_data->{context}->{site_user};
  my $cmd_user = unprefix_uuid($user_id);

  if ( $ctx_user ne $cmd_user ) { 

    ERROR( "$key_id - Site User Mismatch $ctx_user != $cmd_user" );
    return; 
  } 

  return $key_data;
}

sub register_client {
  my ( $self, $activation_token ) = @_;

  my ( $their_pk, $their_key_data ) = $self->get_dh_key();

  my ( $our_dh_pub, $decryptor, $encryptor, $our_dh ) = get_dh_encryptor($their_pk);

  my $resp = $self->request(
    post => "/excollect_api/clients/register",
    body => {
      edh => {
        dhk_id     => $their_key_data->{id}, 
        public_key => $our_dh_pub,
      }, 
      token     => $encryptor->($activation_token),
      client_data => $self->get_client_data,
    },
  );

  FATAL('Client registration failed') if !$resp->is_success;

  my $msg         = $self->get_message($resp);
  my $key_data    = $msg->{data}->{key_data};

  if ( !try { $self->verify_key($key_data) } ) { 
    FATAL("Client Key verification failed") 
  } 

  my $key_id      = $key_data->{id}; 
  my $client_id   = $key_data->{owner_id};
  my $private_key = $decryptor->(delete $key_data->{cipher});

  $self->set_cfg_val( 
    client_id   => $client_id,
    site_id     => $msg->{data}->{site},
    client_name => $msg->{data}->{name}, 
    key_data    => $key_data,
    private_key => $private_key
  );
  $self->_set_key_id($key_id);
  $self->_set_private_key($private_key);
}

sub get_next_job {
  my ($self) = @_;

  my $resp = $self->signed_request(
    post            => $self->uri_base . '/jobs/get_next',
    body            => { client_data => $self->get_client_data },
    expected_errors => [404]
  );

  return if !$resp or !$resp->is_success;

  return $self->get_message($resp);
}

sub get_jobs {
  my ($self) = @_;

  my $resp = $self->signed_request(
    post            => $self->uri_base . '/jobs/get_jobs',
    body            => { client_data => $self->get_client_data },
    expected_errors => [404]
  );

  return if !$resp or !$resp->is_success;

  return $self->get_message($resp);
}

sub get_job {
  my ( $self, $job_id ) = @_;

  my $resp = $self->signed_request( get => $self->uri_base . "/jobs/$job_id" );

  return if !$resp or !$resp->is_success;

  return $self->get_message($resp);
}

sub update_job {
  my ( $self, $job_id, $update ) = @_;

  return $self->signed_request(
    patch      => $self->uri_base . "/jobs/$job_id",
    body       => $update,
    retry      => 3,
    replayable => 1
  );
}

sub add_job_log {
  my ( $self, $job_id, $level, $text, $ts ) = @_;

  my $log = { datetime => $ts, level => $level, text => $text };

  my $resp = $self->signed_request(
    post       => $self->uri_base . "/jobs/$job_id/job_logs",
    body       => [$log],
    retry      => 3, 
    replayable => 1
  );

  if ( $resp && !$resp->is_success ) {
    ERROR( "Failed log update for job $job_id - " . $self->get_error_str($resp) );
  }

  return $resp;
}

sub update_revoked_keys {
  my ( $self ) = @_;

  my $last_check = $self->get_cfg_val('last_revoked_keys_check');

  my $resp = $self->signed_request( 
    get => $self->uri_base .'/get_revoked_keys',
    $last_check 
      ? ( params => { last_update => $last_check } )
      :  ()
  );

  if ( $resp && !$resp->is_success ) {
    ERROR( "Failed to update revoked keys - " . $self->get_error_str($resp) );
    return;
  }

  my $revoked_keys = $self->get_message($resp);

  $self->add_revoked_keys( map { $_->{key_id} } @$revoked_keys );

  $self->set_cfg_val( last_revoked_keys_check => get_timestamp_iso8601(get_utc_timepiece()) );

  return $revoked_keys;
}


1;
