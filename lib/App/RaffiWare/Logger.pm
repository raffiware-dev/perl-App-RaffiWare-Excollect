package App::RaffiWare::Logger;

use strict;
use warnings;  

use Carp qw| longmess |; 
use Moo; 
use Types::Standard qw| :all |;

use RaffiWare::APIUtils::DateTime qw| get_utc_time_stamp_tp |; 

use Exporter 'import';

with 'MooX::Singleton';

our @EXPORT = qw( LOG TRACE DEBUG INFO WARNING ERROR FATAL _log_forked ); 

with 'App::RaffiWare::Role::DoesLogging';

has 'log_dir' => (
  is       => 'ro',
  isa      => Str,
); 

has 'log_file' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_log_file'
); 

sub _build_log_file {
  my $self = shift;

  return sprintf("%s/log", $self->log_dir ); 
}

has 'log_fh' => (
  is      => 'ro',
  isa     => FileHandle,
  lazy    => 1,
  builder => '_build_log_fh',
  clearer => 'clear_log_fh'
);

sub _build_log_fh {
  my $self = shift;

  open my $fh, '>>', $self->log_file or die $!; 

  my $old_fh = select($fh);
  $| = 1;
  select($old_fh);

  return $fh;
} 

around log_message => sub {
  my ( $orig, $class, @args ) = @_; 

  if ( my $instance = __PACKAGE__->instance ) {
     $instance->$orig(@args)
  }

};

sub _log_forked {

  if ( my $instance = __PACKAGE__->instance ) {
     $instance->clear_log_fh
  } 
}

sub _build_msg_handler {

  return sub {

    my ( $self, $level, $msg ) = @_; 

    my $log_line = get_utc_time_stamp_tp() ." $level : $msg\n";

    print $log_line; 

    if ( $self->log_dir && -d $self->log_dir )  {
       my $log = $self->log_fh; 
       print $log $log_line;
    }

  };
} 


sub LOG     { __PACKAGE__->log_message(@_) }
sub TRACE   { __PACKAGE__->log_message('trace', @_)  }
sub DEBUG   { __PACKAGE__->log_message('debug', @_) }
sub INFO    { __PACKAGE__->log_message('info', @_) }
sub WARNING { __PACKAGE__->log_message('warning', @_) }
sub ERROR   { __PACKAGE__->log_message('error', @_ ) }
sub FATAL   { __PACKAGE__->log_message('error', @_ ); die("\n") }

1;
