package App::RaffiWare::Role::HasAPIClient;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;

use App::RaffiWare::API;
use App::RaffiWare::ExCollect::API;

with  'App::RaffiWare::Role::HasCfg';

has 'api_class' => (
  is      => 'ro', 
  isa     => Str,
  default => sub {'App::RaffiWare::API'}
);

has 'api_args' => (
  is      => 'ro', 
  isa     => HashRef,
  lazy    => 1,
  builder => '_build_api_args'
); 

sub _build_api_args { 
   my $self = shift;

   my $api_class = $self->api_class; 

   return $api_class->build_api_args($self);
} 

has 'api' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::API'],
  lazy    => 1,
  builder => '_build_api',
  handles => [qw| signed_api_request |]
); 

sub _build_api { 
   my $self = shift;

   my $api_class   = $self->api_class;
   my $key_id      = $self->get_cfg_val('host_id');
   my $private_key = $self->get_cfg_val('private_key'); 

   return $api_class->instance( 
             cmd_cfg      => $self->cmd_cfg,
             cmd_dir      => $self->cmd_dir,
             api_hostname => $self->get_cfg_val('api_hostname'),
             ( $key_id && $private_key )
               ? ( key_id      => $key_id,
                   private_key => $private_key
                 )
               : (),
             %{$self->api_args}

          ); 
}

1;
