#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { require App::RaffiWare::ExCollect::Worker; }; 

use Test::Most;
use Text::Diff;

use App::RaffiWare::Cfg;

my $cfg_file = "t/cfg/test_lock.yaml";

unlink $cfg_file;

my $cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file );

$cfg->set( short_text => 'hi planet' ); 

my $long_str =<<'END';
some big long
string of multi
line test here
END

$cfg->set( long_text => $long_str );
$cfg->set( this => 'that' );
$cfg->set( number => 2 );
$cfg->set( nested => { some => { struct => [qw|some of thes|] }} ); 

ok(1);
my $cfg2 = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file ); 
$cfg2->set( number => 3 );

$cfg->lock();

is $cfg->get('number'), 3, 'config refreshed after lock';

ok !$cfg2->lock(), 'unable to get lock';

$cfg->unlock();

ok $cfg2->lock(), 'Got lock';

$cfg2->unlock();

# Test concurrent access with locking doesn't result in any config
# file corruption.
for my $child (1..5) {

  my $pid = fork;
  die "failed to fork: $!" unless defined $pid;
  next if $pid;

  my $cfg = App::RaffiWare::Cfg->new( cfg_file =>  $cfg_file ); 

  for ( 1..50 ) {

    my $ret = $cfg->lock();

    if (!$ret) {
      warn("lock timeout '$child'");
      next
    }

    $cfg->set( number => int(rand(100)) ); 
    $cfg->unlock();

  }

  exit;
}
my $kid;

do {
  $kid = waitpid -1, 0;
} while ($kid > 0);

$cfg->clear_yaml;

diag $cfg->get('number');

done_testing();
