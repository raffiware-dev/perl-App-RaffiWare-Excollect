# ./script/exc.PL host-init 
package App::RaffiWare::ExCollect::Cmd::ClientInit;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |;

use Data::Dumper;
use JSON qw| decode_json encode_json |; 

with 'App::RaffiWare::Role::IsCmd',
     'App::RaffiWare::Role::HasAPIClient';

has '+api_class' => (
  default => sub {'App::RaffiWare::ExCollect::API'}
);

has 'activation_token' => (
  is      => 'ro',
  isa     => Str,
  writer  => '_set_activation_token'
);  

sub needs_init { 0 }; 

has 'api_hostname' => (
  is        => 'ro',
  isa       => Str,
  writer    => '_set_api_hostname',
  predicate => 'has_api_hostname'
);  

sub _build_get_opts {
  [ qw|  api-hostname=s help | ] 
}

sub _build_pos_args {
  [ 
    [ '_set_activation_token', 'Activation Token Required', sub { shift } ]  
  ]
}  

sub is_registered { 
   my $self = shift;  

   return ($self->is_initialized && $self->get_cfg_val('host_id')); 
}

sub run {
  my ( $self ) = @_;

  if ( $self->is_registered ) {
      WARNING('Already Registered');
      return 1
  }

  DEBUG("Running ". ref($self)); 

  $self->init_dot_dir();

  $self->init_cfg();

  $self->register_host();

  INFO('Registration complete');

  return 0;
} 


sub init_cfg {
  my ( $self ) = @_;  

  $self->set_cfg_val( 
            $self->cmd_cfg->cfg_defaults,
            $self->has_api_hostname
              ? ( api_hostname => $self->api_hostname )
              : (),
            );
}

sub init_dot_dir {
  my ( $self ) = @_; 

  my $cmd_dir = $self->cmd_dir;

  for my $dir ( 
    $cmd_dir, 
    "$cmd_dir/jobs", 
    "$cmd_dir/archive",  
    "$cmd_dir/replay_cache",
  ) {
    mkdir $dir if !-d $dir;
  }

}

sub register_host {
  my ( $self ) = @_;  

  $self->api->register_host($self->activation_token);

}

1; 

__DATA__

=head1 SYNOPSIS

exc client-init <activation_token>  [--api-hostname https://<hostname>] 

=head1 EXAMPLE
 
  exc client-init 3sFKjsadfASdgvhasdljdf

=head1 ARGUMENTS

=over 4

=item <activation_token>  - Token provided in Client web panel.

=back 

=head1 OPTIONS

=over 4

=item --api-hostname https://<hostname>[:<port>] - Set/Override hostname of ExCollect API endpoint.

=item --help - Print this document

=back

=cut
