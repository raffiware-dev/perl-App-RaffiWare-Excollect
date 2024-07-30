package App::RaffiWare::Role::TakesCmdArgs;

use strict;
use warnings; 

use Moo::Role; 
use Types::Standard qw| :all |; 

use Data::Dumper;
use Getopt::Long;
use Try::Tiny;

requires qw| BUILD argv _build_get_opts _build_pos_args |;

has 'argv' => (
  is       => 'ro',
  isa      => ArrayRef,
  required => 1,
); 

has 'args' => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} }
);  

has 'get_opts' => (
  is       => 'ro',
  isa      => ArrayRef,
  builder  => '_build_get_opts'
); 

has 'pos_args' => (
  is       => 'ro',
  isa      => ArrayRef,
  builder  => '_build_pos_args' 
);  

has 'arg_errors' => (
  is       => 'ro',
  isa      => ArrayRef,
  default  => sub { [] }
); 

before BUILD => sub {
  my ($self) = @_; 

  $self->parse_argv();
};  

sub parse_argv {
  my ( $self ) = @_;

  my $argv = $self->argv;
  my $args = $self->args;
  my $p    = Getopt::Long::Parser->new;

  $p->configure( 'pass_through' );  

  $p->getoptionsfromarray( $argv, $args, @{$self->get_opts} );  


  foreach my $attr ( keys %$args ) {
    my $val = $args->{$attr};

    $attr =~ s/-/_/g;
    $attr = "_set_$attr";

    $self->$attr($val);
  }

  foreach my $pos_arg ( @{$self->pos_args} ) {

    my ( $accessor, $error, $normalizer, $optional ) = @$pos_arg;
    $normalizer ||= sub { @_ };

    if ( (!@$argv and !$optional) or (@$argv and $argv->[0] =~ /^[-]{1,2}/) ) {
      ref($error) eq 'CODE' ? $self->$error() : push( @{$self->arg_errors}, "$error")
    }
    else {
      my $arg_value = shift @$argv or last;

      $self->set_pos_arg( $accessor, $arg_value , $error, $normalizer );
    }
  }

}

sub set_pos_arg {
  my ( $self, $attr, $value, $error, $normalizer ) = @_;  

  try { $self->$attr( $normalizer ? $normalizer->($value) : $value ) } 
  catch { push( @{$self->arg_errors}, "$_") } ; #die "$_ $error\n" };
}  

1;
