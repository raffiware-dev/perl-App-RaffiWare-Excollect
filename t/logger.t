#!/usr/bin/env perl
use strict;
use warnings;


use Test::More;
 
BEGIN { 

  require App::RaffiWare::ExCollect::Worker;

}; 

use_ok('App::RaffiWare::Logger');

unlink "t/log";  

my $logger = App::RaffiWare::Logger->instance( log_level => 'info', log_dir => 't/' );

$logger->log_message('info',  'test log');
$logger->log_message('debug',  'disabled debug log'); 

$logger->set_level('debug');
$logger->log_message('debug',  'enabled debug log');  

done_testing();
