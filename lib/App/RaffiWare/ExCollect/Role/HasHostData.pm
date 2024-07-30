package App::RaffiWare::ExCollect::Role::HasHostData;


use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;  

use App::RaffiWare::ExCollect::HostData;

has 'host_data' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::ExCollect::HostData'],
  lazy    => 1,
  builder => '_build_host_data',
  handles => {
    get_host_data     => 'data',
    get_host_data_val => 'get_data'
  }
); 

sub _build_host_data { App::RaffiWare::ExCollect::HostData->new( cmd_dir => shift->cmd_dir )}


1;
 
