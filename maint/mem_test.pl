#!/usr/bin/env perl

use strict;
use warnings; 


# high mem usage 40 meg delta #
# use Crypt::Random qw| makerandom_itv |;
use DateTime;
use DateTime::Format::ISO8601; 
use Crypt::RFC8188 qw| ece_encrypt_aes128gcm ece_decrypt_aes128gcm |; # 7 megs


# 12 megs
use Crypt::PK::X25519;
use Crypt::PK::Ed25519;
use Crypt::KeyDerivation qw| hkdf |;
use Cwd;
use IO::Stty; 
use IO::Tty::Util qw(forkpty) ; 
use JSON qw| encode_json |;
use MIME::Base64 qw| encode_base64 decode_base64 encode_base64url decode_base64url |;
use Moo; 
use File::HomeDir;
use Proc::Daemon;
use Types::Standard qw| :all |;
use Unicode::Escape;

#use App::RaffiWare::ExCollect::Job; 
#use App::RaffiWare::ExCollect::Job::Logger; 


#use Moo;
#with 'App::RaffiWare::Role::DoesLogging';  
#       'App::RaffiWare::Role::HasCfg';
#      #'App::RaffiWare::Role::HasLogger', 
#      #      'App::RaffiWare::Role::HasAPIClient', 
#      # 'App::RaffiWare::ExCollect::Role::HasJobs';
 

while ( 1 ) { }

1;
