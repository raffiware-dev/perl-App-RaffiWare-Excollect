package App::RaffiWare::ExCollect::Job::Logger;

use strict;
use warnings;

use Moo; 
use Types::Standard qw| :all |;   

use RaffiWare::APIUtils qw| get_utc_time_stamp |;

with 'App::RaffiWare::Role::HasAPIClient', 
     'App::RaffiWare::Role::DoesLogging'; 

has 'job_id' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'job_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'stdout_file' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_stdout_file'
); 

sub _build_stdout_file {
  my $self = shift;

  return sprintf("%s/logs/stdout", $self->job_dir ); 
}

has 'stderr_file' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_stderr_file'
); 

sub _build_stderr_file {
  my $self = shift;

  return sprintf("%s/logs/stderr", $self->job_dir ); 
} 

has 'log_file' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_log_file'
); 

sub _build_log_file {
  my $self = shift;

  return sprintf("%s/logs/log", $self->job_dir ); 
}  


has 'log_fhs' => (
  is      => 'ro',
  isa     => HashRef,
  lazy    => 1,
  builder => '_build_log_fhs'
); 

sub _build_log_fhs {
  my $self = shift;

  my $fh_hash = {};

  foreach my $file (qw| log stdout stderr |) { 

    my $file_path = "${file}_file";

    open my $fh, '>>', $self->$file_path or die $!; 
    $fh_hash->{$file} = $fh;

  }

  return $fh_hash;
} 


has '+api_class' => (
  default => sub {'App::RaffiWare::ExCollect::API'}
);  

sub _build_msg_handler {

  return sub {
           my ( $self, $level, $msg ) = @_; 

           my $ts = get_utc_time_stamp();

           $self->local_job_log($level, $msg, $ts);

           $self->api->add_job_log( $self->job_id, $level, $msg, $ts );
         };
}

around LEVEL_MAP => sub {
  my ( $orig, $class ) = @_;

  return { %{$class->$orig()}, stdout => 99, stderr => 99 };
};


sub local_job_log  {
  my (  $self, $level, $msg, $ts ) = @_; 

  if ( $level eq 'stdout' ) { 
      my $stdout = $self->log_fhs->{stdout};
      print $stdout $msg;
  }
  elsif ( $level eq 'stderr' ) {
      my $stderr = $self->log_fhs->{stderr}; 
      print $stderr $msg;
  }
  else {
      my $log = $self->log_fhs->{log}; 
      print $log "$ts $level : $msg\n"; 
  }
};

1;
