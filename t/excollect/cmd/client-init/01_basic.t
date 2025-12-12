#!/usr/bin/env perl
use strict;
use warnings;

BEGIN { require App::RaffiWare::ExCollect::Worker; };

use Test::More;
use Text::Diff;

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  

use Cwd;


use_ok('App::RaffiWare::ExCollect::Cmd::ClientInit'); 


my $token = 'KKKKKKKKKKKKK'; 
my $cwd   = getcwd(); 

unlink "$cwd/t/ecollect/cmd/client-init/exc.cfg";

my $argv = [ $token, '--api-hostname', 'https://testserver.io'];

my $init_cmd = App::RaffiWare::ExCollect::Cmd::ClientInit->new( 
  argv    => $argv, 
  cmd_dir => "$cwd/t/excollect/cmd/client-init"
); 

isa_ok $init_cmd, 'App::RaffiWare::ExCollect::Cmd::ClientInit';
is $init_cmd->activation_token => $token, 'activation token set';

is $init_cmd->api_hostname => 'https://testserver.io', 'api_hostname set';

$init_cmd->init_cfg();

is $init_cmd->get_cfg_val('api_hostname') => 'https://testserver.io', 'api_hostname set in cfg'; 

is $init_cmd->api->api_hostname => 'https://testserver.io', 'api_hostname set api instance';  


done_testing();
