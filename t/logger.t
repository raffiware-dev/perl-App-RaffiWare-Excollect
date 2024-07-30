#!/usr/bin/env perl
use strict;
use warnings;


use Test::More;
 
BEGIN { 

  use FindBin;
  my $fatbin = "$FindBin::Bin/../bin/exc"; 
  require $fatbin if -f $fatbin;

}; 

use_ok('App::RaffiWare::Logger');

unlink "$FindBin::Bin/log";  

diag $FindBin::Bin;
my $logger = App::RaffiWare::Logger->instance( level => 'info', log_dir => "$FindBin::Bin" );

$logger->log_message('info',  'test log');
$logger->log_message('debug',  'disabled debug log'); 

$logger->set_level('debug');
$logger->log_message('debug',  'enabled debug log');  

done_testing();
