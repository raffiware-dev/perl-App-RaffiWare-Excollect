package App::RaffiWare::Role::HasLogger;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;  

use App::RaffiWare::Cfg;

with  'App::RaffiWare::Role::HasCfg'; 

has 'logger' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Logger'],
  lazy    => 1,
  builder => '_build_logger',
  handles => [qw| 
    log_message 
    log_level
    set_level 
    debugging_enabled 
  |]
); 

sub _build_logger { 
  my $self = shift;

  require App::RaffiWare::Logger;

  my $log_level = $self->cfg_exists
                    ? $self->cmd_cfg->get('log_level') || 'info'
                    : 'info';

  return App::RaffiWare::Logger->instance( log_level => $log_level, log_dir => $self->cmd_dir );
}

1;
