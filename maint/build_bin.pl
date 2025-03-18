#!/usr/bin/env perl

use Config;
use Sys::GNU::ldconfig;

 
my $libcv       = $Config{gnulibc_version};
my ($arch)      = $Config{archname} =~ /^([^-]+)-/;
my ($libcryptv) = ld_lookup("libcrypt") =~ /\.([1-9])$/; 

my $binary = "exc.par-$arch-$libcv-$libcryptv"; 

#open(my $fh, '-|', 'maint/bin_name.pl') or die $!;
#my $binary = do { local $/ = undef; <$fh> };
#close $fh;


#  /usr/sbin/ldconfig -p | grep 'libcrypt.so\.'
#       libcrypt.so.1 (libc6,x86-64) => /lib/x86_64-linux-gnu/libcrypt.so.1 
system(q| cp script/exc.PL binaries/exc |);
system(q| cp script/anyevent-fork.PL binaries/anyevent-fork |);
system(qq| pp -I lib -M Text::Template::* -M MooX::HandlesVia  -M Mo -M Mo::builder -M Mo::default -M Crypt::PK::* -o binaries/$binary binaries/exc binaries/anyevent-fork maint/inc_script.pl  |);
system(qq| rm binaries/exc binaries/anyevent-fork |); 
 
