package App::RaffiWare::ExCollect::Role::HasClientData;


use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;  

use App::RaffiWare::ExCollect::ClientData;

has 'client_data' => (
  is      => 'ro',
  isa     => InstanceOf['App::RaffiWare::ExCollect::ClientData'],
  lazy    => 1,
  builder => '_build_client_data',
  handles => {
    get_client_data     => 'data',
    get_client_data_val => 'get_data'
  }
); 

sub _build_client_data { App::RaffiWare::ExCollect::ClientData->new( cmd_dir => shift->cmd_dir )}


1;
 
