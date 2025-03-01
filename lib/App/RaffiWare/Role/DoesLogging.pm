package App::RaffiWare::Role::DoesLogging;

use strict;
use warnings;  

use Moo::Role; 
use Types::Standard qw| :all |;   

my %LEVEL_MAP = (
   trace     => 1,
   debug     => 2,
   info      => 3,
   warning   => 4,
   error     => 5,
);

sub LEVEL_MAP {
  return \%LEVEL_MAP
}

has 'level' => (
  is       => 'ro',
  isa      => Str,
  default  => sub { 'info' },
  writer   => 'set_level'
); 

has 'msg_handler' => (
  is       => 'ro',
  isa      => CodeRef,
  lazy     => 1,
  builder  => '_build_msg_handler'
); 

sub _build_msg_handler {

  return sub {
    my ( $self, $level, $msg ) = @_; 

    print uc($level) ." - $msg\n"  
  };
}

sub log_message {
  my ( $self, $level, $msg, @args ) = @_;

  my $level_map = $self->LEVEL_MAP;

  return unless $level_map->{$level} and $level_map->{$level} >= $level_map->{$self->level};

  $self->msg_handler->($self, $level, $msg, @args);
}


1;
