#!/usr/bin/env perl

use FindBin;
use lib  "$FindBin::Bin/../lib"; 

use App::RaffiWare::ExCollect;

use Config;
use File::Copy;
use File::Find;
use File::pushd;
use File::Path qw( make_path rmtree ); 
use Sys::GNU::ldconfig;

use Cwd;
my $dir = getcwd;


my $version = $App::RaffiWare::ExCollect::VERSION; 
my $distdir = "App-RaffiWare-ExCollect-$version";

rmtree($distdir);


unlink 'MANIFEST' if -f 'MANIFEST';
system('make clean');


system('perl Makefile.PL'); 
system('make manifest');
system('make distdir'); 

unlink "$distdir/cpanfile";

copy "cpanfile.dist" => "$distdir/cpanfile";
copy "cpanfile.dist.snapshot" => "$distdir/cpanfile.snapshot";

# Reuse carton builds when available.
symlink "$dir/distlocal" => "$distdir/local" if -d "$dir/distlocal"; 


system("cp -R fatlib $distdir/fatlib");

{
   my $pushd = pushd $distdir;

   my $strip_pm = sub {
       if ( /\.pm$/ ) {
           print "strip $_\n";
           system("perlstrip --cache -v $_");
       }
   }; 

   find({ wanted => $strip_pm, no_chdir => 1 }, "lib");  

   # Fix $VERSION broken by perlstrip for MakeMaker .
   system(q|perl -p -i -e 's/;(our\$VERSION=".+";)\s*(\$VERSION=eval\$VERSION;\s*)/;\n\n$1\n$2\n\n/' lib/App/RaffiWare/ExCollect.pm|);

   mkdir 'bin';
   system('fatpack file script/exc.PL > bin/exc');
   system('fatpack file lib/App/RaffiWare/ExCollect/Worker.pm > Worker.pm'); 
   system('cp script/anyevent-fork.PL bin/anyevent-fork');


   if ( !-f "$dir/install/vendor-cache.tar.gz" ) {
       # Build new carton lib if we don't have one and create
       # vendor package cache. 
       system(' carton install ') if !-l "$distdir/local";
       system(' carton bundle '); 
       system(' tar -czvf vendor-cache.tar.gz vendor ');
   }

   # Clean up unneeded build files libs that are now fatpacked into bin/exc
   for (
     qw|
       lib/App/RaffiWare/Role/HasLogger.pm
       lib/App/RaffiWare/Role/TakesCmdArgs.pm
       lib/App/RaffiWare/Role/IsCmd.pm
       lib/App/RaffiWare/Role/DoesLogging.pm
       lib/App/RaffiWare/Role/HasCfg.pm
       lib/App/RaffiWare/Role/HasAPIClient.pm
       lib/App/RaffiWare/Cfg.pm
       lib/App/RaffiWare/ExCollect/Worker.pm
       lib/App/RaffiWare/Logger.pm
       lib/App/RaffiWare/API.pm  
       script/exc.PL
       script/anyevent-fork.PL
       MANIFEST
     |
   ) {
     unlink $_;
   }
   
   for (
     qw|
        fatlib
        install
        lib/App/RaffiWare/ExCollect
        lib/App/RaffiWare/Role
        vendor 
        binaries
     |
   ) {
     rmtree($_);
   }


   if ( ! -d "$dir/distlocal" ) {
     move local => "$dir/distlocal" 
   }
   else {
     rmtree('local')
   } 


   mkdir 'lib/App/RaffiWare/ExCollect';

   # Fat packed for AnyEvent::Fork::Serve processes to require
   move 'Worker.pm' => 'lib/App/RaffiWare/ExCollect/Worker.pm';

   system('perl Makefile.PL'); 
   system('make manifest');
   system('make dist');  
}

if ( !-f "$dir/vendor-cache.tar.gz" ) {
    move "$distdir/vendor-cache.tar.gz" => "$dir/vendor-cache.tar.gz";
}

my $archive = "App-RaffiWare-ExCollect-$version.tar.gz";

move "$distdir/$archive" => $archive;
