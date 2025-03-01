package App::RaffiWare::ExCollect::API;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use RaffiWare::APIUtils qw| get_utc_time_stamp get_utc_datetime
                            get_timestamp_iso8601 make_uri_uuid |;

use App::RaffiWare::Logger;
use App::RaffiWare::Cfg;

use HTTP::Request::Common;
use HTTP::Thin;
use HTTP::Request;
use JSON qw| decode_json encode_json |;
use DateTime;
use Data::Dumper;
use URI;

extends 'App::RaffiWare::API';

has 'uri_base' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_uri_base'
);

sub _build_uri_base {
  my $self = shift;

  return sprintf( "/excollect_api/hosts/%s", $self->get_cfg_val('host_id') );
}

has 'keys' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_load_keys',
  handles => {
    _get_user_key => 'get',
    add_user_key  => 'set',
  }
);

sub _load_keys {
  my $self = shift;

  my $key_file = sprintf( '%s/keys', $self->cmd_dir );

  return App::RaffiWare::Cfg->new( cfg_file => $key_file );
}

with 'App::RaffiWare::ExCollect::Role::HasHostData';

sub get_command_user_key {
  my ( $self, $job_id, $user_id ) = @_;

  my $key_data = $self->_get_user_key($user_id);

  if ( !$key_data ) {
    my $resp = $self->signed_request( 
                        get => $self->uri_base ."/jobs/$job_id/command_instance/command/all_users/$user_id/public_key" );

    if ( $resp && !$resp->is_success ) {
      ERROR( "Failed to fetch key for $user_id - " . $self->get_error_str($resp) );
      return;
    }

    $key_data = $self->get_message($resp);

    $self->add_user_key( $user_id, $key_data );
  }

  return $key_data;
}

sub build_api_args {
  my ( $class, $cmd ) = @_;

  return +{ cmd_dir => $cmd->cmd_dir };
}

sub register_host {
  my ( $self, $activation_token ) = @_;

  my $resp = $self->request(
                      post => "/excollect_api/hosts/register",
                      body => {
                        token     => $activation_token,
                        host_data => $self->get_host_data,
                      }
                    );

  FATAL('Host registration failed') if !$resp->is_success;

  my $msg         = $self->get_message($resp);
  my $host_id     = $msg->{data}->{id};
  my $public_key  = $msg->{data}->{public_key};
  my $private_key = $msg->{data}->{private_key};

  $self->set_cfg_val( host_id => $host_id, public_key => $public_key, private_key => $private_key );
  $self->_set_key_id($host_id);
  $self->_set_private_key($private_key);
}

sub get_next_job {
  my ($self) = @_;

  my $resp = $self->signed_request(
                      post            => $self->uri_base . '/jobs/get_next',
                      body            => { host_data => $self->get_host_data },
                      expected_errors => [404]
                    );

  return if !$resp or !$resp->is_success;

  return $self->get_message($resp);
}

sub get_jobs {
  my ($self) = @_;

  my $resp = $self->signed_request(
                      post            => $self->uri_base . '/jobs/get_jobs',
                      body            => { host_data => $self->get_host_data },
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

1;
