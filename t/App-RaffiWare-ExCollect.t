use strict;
use warnings;

# fatpack fix
BEGIN { require App::RaffiWare::ExCollect::Worker; }; 

use Test::More tests => 7;

use_ok('App::RaffiWare::ExCollect');
use_ok('App::RaffiWare::ExCollect::API');
use_ok('App::RaffiWare::ExCollect::Cmd');
use_ok('App::RaffiWare::ExCollect::ClientData');
use_ok('App::RaffiWare::Logger'); 
use_ok('App::RaffiWare::API'); 
use_ok('App::RaffiWare::Cfg'); 
