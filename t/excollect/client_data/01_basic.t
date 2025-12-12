#!/usr/bin/env perl
#
use strict;
use warnings;

# fatpack fix
BEGIN { require App::RaffiWare::ExCollect::Worker; };  

use Test::More;
use Test::Deep;
use Text::Diff;

use RaffiWare::APIUtils qw| prefix_uuid unprefix_uuid make_uri_uuid |;  

use Cwd;
my $cwd  = getcwd(); 


use_ok('App::RaffiWare::ExCollect::ClientData'); 


my $host_data = App::RaffiWare::ExCollect::ClientData->new( 
  cmd_dir => "$cwd/t/excollect/client_data"
); 

cmp_deeply(
  $host_data->data,
  all( 
    code( sub{ ref($_[0]) eq 'ARRAY' } ),
    array_each({
       name        => code( sub{ !!$_[0] } ),
       description => code( sub{ !!$_[0] } ), 
       value_type  => code( sub{ !!$_[0] } ), 
       value       => code( sub{ !!$_[0] } ), 
    })
  ),
  'Expected Client Data format'
);

done_testing();
