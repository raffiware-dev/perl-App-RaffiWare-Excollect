package App::RaffiWare::Role::HasCfg;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;

use App::RaffiWare::Cfg;

has 'cfg_file' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,  
  writer  => '_set_cfg_file',
  builder => '_build_cfg_file'
); 

sub _build_cfg_file { return shift->cmd_dir .'/exc.cfg' } 

sub cfg_exists { -f shift->cfg_file } 

has 'cmd_cfg' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::Cfg'],
  lazy    => 1,
  builder => '_build_cmd_cfg',
  handles => {
    get_cfg_val => 'get',
    set_cfg_val => 'set',
    lock_cfg    => 'lock',
    unlock_cfg  => 'unlock'
  }
); 

sub _build_cmd_cfg { App::RaffiWare::Cfg->new( cfg_file => shift->cfg_file )}

1;
