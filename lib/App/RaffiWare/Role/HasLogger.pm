package App::RaffiWare::Role::HasLogger;


use strict;
use warnings;


use Moo::Role;
use Types::Standard qw| :all |;  

use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

with  'App::RaffiWare::Role::HasCfg'; 

has 'logger' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Logger'],
  lazy    => 1,
  builder => '_build_logger',
  handles => [qw| log_message set_level |]
); 

sub _build_logger { 
   my $self = shift;

   my $log_level = $self->cfg_exists
                     ? $self->cmd_cfg->get('log_level') || 'info'
                     : 'info';

   return App::RaffiWare::Logger->instance( level => $log_level, log_dir => $self->cmd_dir  );
}



1;
