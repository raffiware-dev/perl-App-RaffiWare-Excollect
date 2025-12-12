#!/usr/bin/env perl
#
use strict;
use warnings;

# Fragile test that can break and hang. Needs improvement.

BEGIN { 

  use FindBin;

  require App::RaffiWare::ExCollect::Worker;

  use lib qw|t/lib|;
  use Test::ExCollectWorker; # disabled command_verification  

  # Contains bashrc that sets expected prompt
  $ENV{HOME} = "$FindBin::Bin/fixtures"
}; 

use Test::More tests => 10;
use Test::Deep; 

use RaffiWare::APIUtils qw| 
  prefix_uuid 
  unprefix_uuid 
  make_uri_uuid 
  decode_bin 
  gen_signature
|;

use App::RaffiWare::Logger;
use App::RaffiWare::Cfg;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Fork;
use Crypt::PK::X25519; 
use Crypt::PK::Ed25519; 
use Crypt::KeyDerivation qw| hkdf |;
use Crypt::RFC8188 qw| ece_encrypt_aes128gcm ece_decrypt_aes128gcm |;
use Data::Dumper;
use Text::Diff;
use File::Path qw( make_path rmtree ); 
use MIME::Base64 qw| encode_base64 decode_base64 encode_base64url decode_base64url |; 
use Unicode::Escape; 
use YAML qw| LoadFile |;

my $fixtures = LoadFile("$FindBin::Bin/fixtures/shell_manager.yaml");

my ($encryptors, $decryptors) = ({}, {});

my $key_store  = App::RaffiWare::Cfg->new( 
  cfg_file    => "$FindBin::Bin/fixtures/keys", 
  cfg_storage => 'json' 
);

my $user1_data  = setup_user('user_1');
my $user2_data  = setup_user('user_2');

my $prompt_re = '\$\s[^[:print:]]*';
my $CMD = 0;
my @CMDS = (
 { input  => { 
     ident  => 1, 
     cmd    => 'spawn_shell', 
     user   => $user1_data->{user_id},
     dh     => $user1_data->{dh_pub}, 
     dh_sig => $user1_data->{sig},
     key_id => $user1_data->{key_id}
   },
 },
 { output => qr/^new shell spawned$/,
   cb => sub {
     my $struct = shift;

     setup_cryptors( $struct, $user1_data->{dh_pk} );

     diag 'client setup complete';
   }
 },
 { output => qr/$prompt_re/ },
 { input  => { 
     cmd  => 'shell_in', 
     user => $user1_data->{user_id}, 
     data => "echo 'hi'; echo 'next'\r" } 
 },
 { output => qr/$prompt_re/ }, 
 { input  => { 
     cmd  => 'shell_in', 
     user => $user1_data->{user_id}, 
     data => "free -m\r" } }, 
 { output => qr/$prompt_re/ },
 { input => { 
     cmd  => 'shell_in', 
     user => $user1_data->{user_id}, 
     data => "echo \$EXC_USER\r" } 
 },
 { output => qr/$prompt_re/ },
 { input  => { 
     cmd => 'spawn_shell', 
     user => $user2_data->{user_id} } 
 },
 { error => 1 },
 { input  => { 
     ident  => 1, 
     cmd    => 'spawn_shell', 
     user   => $user2_data->{user_id},
     dh     => $user2_data->{dh_pub}, 
     dh_sig => $user2_data->{sig},
     key_id => $user2_data->{key_id} 
   },
 },
 { output => qr/^new shell spawned$/,
   cb => sub {
     my $struct = shift;

     diag 'starting client setup';

     setup_cryptors( $struct, $user2_data->{dh_pk} );

     diag 'client setup complete';
   }
 }, 
 { output => qr/$prompt_re/ }, 
 { input  => { 
     cmd  => 'shell_in', 
     user => $user2_data->{user_id}, 
     data => "echo \$EXC_USER\r" } 
 },
 { output => qr/$prompt_re/ }, 
 { input  => { 
     cmd  => 'shell_in', 
     user => $user1_data->{user_id}, 
     data => "echo \$EXC_USER\r" } 
 },
 { output => qr/$prompt_re/ },
 { input => { cmd => 'shutdown' } }
);

my ( $cv, $r, $w ) = build_test_controller();

my $to = AE::timer 10, 0,
  sub {
    fail "Timeout";
    $w->push_write( json => { cmd => 'shutdown' } ); 
  };

$w->push_write( json => $CMDS[$CMD++]->{input});

$cv->recv;

# Fix for TAP
print "\n";    

sub build_test_controller {

  my $cv = AE::cv;

  pipe my $from_parent, my $to_child;
  pipe my $from_child,  my $to_parent;

  $to_child->autoflush(1);
  $to_parent->autoflush(1); 

  my $w = new AnyEvent::Handle
    fh      => $to_child,
    on_error => sub {
       my ($hdl, $fatal, $msg) = @_;

       warn("Writer error: $msg");
       $hdl->destroy;
    };

  my $r = new AnyEvent::Handle
    fh      => $from_child,
    on_read => sub {
      my ($hdl) = @_;

      $hdl->unshift_read(json => sub {
        my ( $hdl, $cmd_struct ) = @_;

        my $user = $cmd_struct->{user};

        $decryptors->{$user}->($cmd_struct) if $decryptors->{$user};

        my $cur_cmd = $CMDS[$CMD];

        if ( my $cb = $cur_cmd->{cb} ) {
          $cb->($cmd_struct)
        }

        if ( $cmd_struct->{error} ) {

          if ( $cur_cmd->{error} && $cur_cmd->{error} eq '1' ) {

            pass('expected error: '. $cmd_struct->{error} );

            my $next = $CMDS[ ++$CMD ] or return;

            if ( my $input = $next->{input} ) {

              $user = $input->{user};
              $encryptors->{$user}->($input) if $user and $encryptors->{$user};

              $w->push_write( json => $input );
              $CMD++;
            }

          }
          elsif ( $cur_cmd->{error} ) {
            is( $cur_cmd->{error}, $cmd_struct->{error}, 'expected error' )
          }
          else {
            fail('unexpected error : '. $cmd_struct->{error} );

            $w->push_write( json =>  { cmd => 'shutdown' } );
          }
        }

        if ( $cur_cmd->{output}
            and $cmd_struct->{data}
            and $cmd_struct->{data} =~ $cur_cmd->{output}
        ) {

          pass('Got expected output');

          my $next = $CMDS[ ++$CMD ];

          if ( $next and my $input = $next->{input} ) {

            $user = $input->{user}; # || '';
            $encryptors->{$user}->($input) if $user && $encryptors->{$user};

            $w->push_write( json => $input );
            $CMD++;
          }
        }

        diag Unicode::Escape::unescape($cmd_struct->{data}) if $cmd_struct->{data};

      });

    },
    on_error => sub {
       my ($hdl, $fatal, $msg) = @_;

       warn("Reader error: $msg");
       $hdl->destroy;
    },
    on_eof => sub {

      $cv->send;
    };

  AnyEvent::Fork
   ->new
   ->require ("App::RaffiWare::ExCollect::Worker")
   ->send_fh( $from_parent, $to_parent )
   ->send_arg("$FindBin::Bin/fixtures")
   ->run ("App::RaffiWare::ExCollect::Worker::shell_manager",
       sub {
         my ($fh) = @_;

         my $hdl2 = new AnyEvent::Handle
           fh      => $fh,
           on_read => sub {
             my ($hdl) = @_;

             $hdl->unshift_read ( json => sub {
                my ($hdl, $struct) = @_;

                #diag explain $struct;
                my $shutdown = ( $struct->{warning} and $struct->{warning} eq 'Got Shutdown' );

                $cv->send && $hdl->destroy if $shutdown;
             });

           },
           on_eof => sub {
             $cv->send
           },
           on_error => sub {
             my ($hdl, $fatal, $msg) = @_;

             warn("ERRROR $msg");
             AE::log error => $msg;
             $hdl->destroy;
             $cv->send;
           };
       });

  return ($cv, $r, $w);
}

sub setup_user {
  my $fixture_user = shift;

  my $key_data  = $fixtures->{$fixture_user}->{key_data};
  my $key_id    = $key_data->{id};
  my $user_id   = prefix_uuid('su', $key_data->{context}->{site_user}); 
  my $priv_key  = $fixtures->{$fixture_user}->{private_key}; 
  my $user_pk   = Crypt::PK::Ed25519->new(\decode_bin($priv_key)); 

  $key_store->set( $key_id => $key_data );

  # User ECDH key
  my $dhk = Crypt::PK::X25519->new();
  $dhk->generate_key; 

  # Sign user ECDH key with exc key.
  my $dh_der = $dhk->export_key_der('public'); 
  my $sig    = $user_pk->sign_message($dh_der);
  my $sig_64 = encode_base64url($sig);
  my $dh_enc = encode_base64url($dh_der); 

  return {
     user_id => $user_id,
     key_id  => $key_id,
     dh_pk   => $dhk,
     dh_pub  => $dh_enc,
     sig     => $sig_64,
  };
}

sub setup_cryptors {
  my ($struct, $user_dh_pk) = @_;

  my $user     = $struct->{user};
  my $dh       = $struct->{dh} or return;
  my $their_dh = Crypt::PK::X25519->new( \decode_base64url($dh) ); 
  my $secret   = $user_dh_pk->shared_secret($their_dh);

  $encryptors->{$user} = sub {
     my $struct = shift;

     return if (!$struct->{cmd} or $struct->{cmd} ne 'shell_in'); 

     my $plaintext = $struct->{data};

     my $secret_128bit = hkdf($secret, '', 'SHA256', 16, "Content-Encoding: aes128gcm\x00" );
     my $cipher        = ece_encrypt_aes128gcm( $plaintext, undef, $secret_128bit );

     $struct->{data} = encode_base64url($cipher);
  };

  $decryptors->{$user} = sub {
     my $struct = shift; 

     return if (!$struct->{cmd} or $struct->{cmd} ne 'shell_out');

     my $cipher        = decode_base64url($struct->{data});
     my $secret_128bit = hkdf($secret, '', 'SHA256', 16, "Content-Encoding: aes128gcm\x00" );

     $struct->{data} = ece_decrypt_aes128gcm( $cipher, $secret_128bit );
  }; 

}

