package Test::ExCollectWorker;

use strict;
use warnings; 

use Moo;
use App::RaffiWare::ExCollect::Worker; # load fatpack libs
use App::RaffiWare::ExCollect::Job; 

extends 'App::RaffiWare::ExCollect::Worker'; 

no warnings 'redefine';
*App::RaffiWare::ExCollect::Job::verify_command_signature = sub { warn("no command verification\n"); 1 };



1; 
