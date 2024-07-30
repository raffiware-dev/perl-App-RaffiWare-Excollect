package App::RaffiWare::API;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use RaffiWare::APIUtils qw| sign_exc_request get_utc_time_stamp get_utc_datetime 
                            get_timestamp_iso8601 inflate_iso8601_datetime |; 

use App::RaffiWare::Logger;

use HTTP::Request::Common;
use HTTP::Thin; 
use HTTP::Request;
use JSON qw| decode_json encode_json |;
use DateTime;
use Data::Dumper; 
use URI;


with 'MooX::Singleton',
     'App::RaffiWare::Role::HasLogger', 
     'App::RaffiWare::Role::HasCfg'; 

has 'api_hostname' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'user_agent' => (
  is      => 'ro',
  isa     => InstanceOf['HTTP::Thin'],
  lazy    => 1,
  builder => '_build_user_agent' 
); 

sub _build_user_agent { HTTP::Thin->new() }  


has 'last_api_time_offset_update' => (
   is        => 'rw',
   isa       => InstanceOf['DateTime'],
   lazy      => 1,
   builder   => '_build_last_api_time_offset_update',
   writer  => '_set_last_api_time_offset_update' 
); 

sub _build_last_api_time_offset_update {
    my $self = shift;

    return inflate_iso8601_datetime($self->get_cfg_val('last_api_time_offset_update'))
}

sub set_last_api_time_offset_update { 
    my $self = shift;

    my $dt = get_utc_datetime();

    $self->set_cfg_val( last_api_time_offset_update => get_timestamp_iso8601($dt) ); 
    $self->_set_last_api_time_offset_update($dt);
}

sub has_api_time_offset { shift->get_cfg_val('last_api_time_offset_update') }

has 'api_time_offset' => (
   is      => 'rw',
   isa     => Int,
   lazy    => 1,
   builder => 'update_api_time_offset',
   writer  => '_set_api_time_offset',
   default => sub { 0 }
);  

sub set_api_time_offset {
    my ( $self, $offset ) = @_;  

    $self->set_last_api_time_offset_update();  
    $self->_set_api_time_offset($offset);
}


our $OFFSET_UPDATE_INT = 12; # hours 

sub needs_api_time_offset_update {
    my ($self) = @_; 

    return 1 if !$self->has_api_time_offset;

    my $last_dt = $self->last_api_time_offset_update();
    my $dt_now  = get_utc_datetime(); 
    my $delta   = $last_dt->subtract_datetime_absolute($dt_now)->hours;

    return ($delta > $OFFSET_UPDATE_INT);
}

sub update_api_time_offset {
    my ($self) = @_; 

    my $dt   = get_utc_datetime(); 
    my $req  = $self->_build_request( POST => '/time_offset', body => { timestamp => get_timestamp_iso8601($dt) });
    my $resp = $self->_do_request($req);

    if ( !$resp->is_success ) {
        WARNING("API time offset update failed: \n". $resp->decoded_content );
        return undef;
    }

    my $offset = decode_json($resp->decoded_content)->{message}->{offset};

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
   predicate => 'has_private_key' ,
   writer    => '_set_private_key'
); 

sub has_key { $_[0]->has_key_id && $_[0]->has_private_key }

sub build_api_args {
  my ($class, $cmd) = @_;

  return +{}
} 

sub request {
    my ($self, $method, $path, %args ) = @_;

    return if $self->get_cfg_val('local_only');

    my $req = $self->_build_request( $method, $path, %args ); 

    return $self->_do_request($req, %args);
}

sub signed_request {
    my ($self, $method, $path, %args ) = @_;

    return if $self->get_cfg_val('local_only'); 

    if ( !$self->has_key ) {
        WARNING('No credentials configured');
        return
    }

    my $req         = $self->_build_request( $method, $path, %args ); 
    my $key_id      = $self->key_id;
    my $private_key = $self->private_key; 

    $self->update_api_time_offset() 
        if $self->needs_api_time_offset_update;

    my $tokens;
    ($req, $tokens) = sign_exc_request( $key_id, $req, $private_key, $self->api_time_offset );
    DEBUG(Dumper($tokens));
    DEBUG(Dumper($req));

    return $self->_do_request($req, %args);
} 

sub _build_request {
    my ( $self, $method, $path, %args ) = @_; 

    my $body    = $args{body};
    my $params  = $args{params};
    my $headers = $args{headers} || {};  

    my $uri = URI->new( $self->api_hostname . $path );

    $uri->query_form(%$params) if $params; 

    my @req_args = ($uri, %$headers);

    push @req_args, ( 'Content-type' => 'application/json;charset=utf-8', 'Content' => encode_json($body)) 
        if $body; 

    my $map = { 
       head   => \&HEAD,
       get    => \&GET,
       post   => \&POST,
       put    => \&PUT,
       patch  => \&PATCH,
       delete => \&DELETE
    };   

    return $map->{lc($method)}->(@req_args);  
}

sub _do_request {
  my ($self, $req, %args) = @_;

  my $retriable       = $args{retry}      || 0;
  my $replayable      = $args{replayable} || 0;
  my %expected_errors = ( map { ($_ => 1) } @{$args{expected_errors} || []} ); # || ();  

  # TODO retry requests a few times on failure
  # freeze req to thaw and retry later.
  # Time::HiRes::time() file prefix
  # only for post/patch requests
  # only on 5xx erros
  my $resp = do { local $SIG{__DIE__}; $self->user_agent->request($req) };

  if (!$resp->is_success && !$expected_errors{$resp->code} ) {
      my $code_type = substr($resp->code, 0,1);
      my $err       = $self->get_error($resp);
      ERROR(sprintf('API ERROR %i : %s',  $err->{error_type_id}, $err->{error}) );
  }

  return $resp; 
}

sub replay_requests {
  # will need to re-sign with updated time

}

sub freeze_request {


} 

sub get_error {
  my ($self, $resp) = @_;

  return if $resp->is_success; 

  if ( $resp->header('content-type') eq 'application/json' ) {
     my $json = decode_json($resp->decoded_content); 

     return { error => $json->{error}, error_type_id => $json->{error} };
  }
  else {
     return { error => $resp->content, error_type_id => $resp->code }; 
  }
}  

sub get_error_str {
  my ($self, $resp) = @_; 

  my $err = $self->get_error($resp) or return;

  return sprintf('%s - %s', $err->{error_type_id}, $err->{error});
}

sub get_message {
  my ( $self, $resp ) = @_;

  return if !$resp->is_success; 

  my $json = decode_json($resp->decoded_content); 

  return $json->{message};
}   

1; 
