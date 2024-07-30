#!/usr/bin/env perl 

use strict;
use warnings;

use File::Path qw( make_path rmtree );  
use File::pushd;


my $workdir = 'workdir';
rmtree($workdir);
mkdir $workdir; 

symlink "local" => "$workdir/local";

{
   my $pushd = pushd $workdir;

   fatpack_file('../install/local_lib.pl', qw|local::lib|); 
   fatpack_file('../install/bin_name.pl');  
}

sub fatpack_file {
  my ($file, @modules) = @_;

  unlink 'packlists';
  rmtree('fatlib');

  my ($prefix) = $file =~ /^(.*)\.pl$/;

  my $extra = (scalar @modules) ? join(' ', map {"--use=$_"} @modules  )  : '';
  my $trace = sprintf(" carton exec fatpack trace %s $file", $extra );

  system($trace);
  system(" carton exec fatpack packlists-for `cat fatpacker.trace` >packlists ");
  system(" carton exec fatpack tree `cat packlists` "); 
  system(" carton exec fatpack file $file > $prefix.packed.pl");  

}
