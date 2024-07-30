#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Text::Diff;

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  

use Cwd;
my $cwd  = getcwd(); 


use_ok('App::RaffiWare::ExCollect::HostData'); 


my $host_data = App::RaffiWare::ExCollect::HostData->new( cmd_dir => "$cwd/t/excollect/host_data"); 

diag explain $host_data->data;

diag explain $host_data->get_data('Uptime');

done_testing();

 
