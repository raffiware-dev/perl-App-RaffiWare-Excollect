#!/usr/bin/env perl

use File::Copy;
use File::Find;
use File::Path qw( rmtree );
use Config;;



if ( !-d './local' ) {
  system(qw| carton install  |); 
}
else {
  print "Using existing local directory\n";
}

rmtree("fatlib"); 

unlink 'fatpacker.trace';
unlink 'packlists';


system(" carton exec fatpack trace maint/inc_script.pl ");
system(" carton exec fatpack packlists-for `cat fatpacker.trace` >packlists ");
system(" carton exec fatpack tree `cat packlists` ");

rmtree("fatlib/$Config{archname}");


my $pod_script_del = sub {
    if ( /\.(p(od|l)|txt)$/ ) {
        unlink $_;
    }
};

find({ wanted => $pod_script_del, no_chdir => 1 }, "fatlib");

my $strip_pm = sub {
    if ( /\.pm$/ ) {
        system("perlstrip --cache -v $_");
    }
}; 

find({ wanted => $strip_pm, no_chdir => 1 }, "fatlib"); 



