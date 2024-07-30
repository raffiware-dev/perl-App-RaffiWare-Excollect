#!/usr/bin/env perl


use Config;
use Sys::GNU::ldconfig;

 
# Create PAR executable for current arch/libc version. 
my $libcv       = $Config{gnulibc_version};
my ($arch)      = $Config{archname} =~ /^([^-]+)-/;
my ($libcryptv) = ld_lookup("libcrypt") =~ /\.([1-9])$/; 

print "exc.par-$arch-$libcv-$libcryptv";
