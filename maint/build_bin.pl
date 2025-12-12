#!/usr/bin/env perl

use Config;
use Sys::GNU::ldconfig;

 
my $libcv       = $Config{gnulibc_version};
my ($arch)      = $Config{archname} =~ /^([^-]+)-/;
my ($libcryptv) = ld_lookup("libcrypt") =~ /\.([1-9])$/; 

my $binary = "exc.par-$arch-$libcv-$libcryptv"; 

system(q| cp script/exc.PL binaries/exc |);
system(q| cp script/anyevent-fork.PL binaries/anyevent-fork |);
system(qq| pp -I lib -M MooX::HandlesVia  -M Mo -M Mo::builder -M Mo::default -o binaries/$binary binaries/exc binaries/anyevent-fork maint/inc_script.pl |);

system(qq| rm binaries/exc binaries/anyevent-fork |); 
 
