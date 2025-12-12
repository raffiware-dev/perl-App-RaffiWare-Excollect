package App::RaffiWare::Role::IsCmd;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw| :all |;

use App::RaffiWare::Cfg;
use App::RaffiWare::Logger;

use File::HomeDir;
use Pod::Text;
use Sys::Hostname; 
use Sys::Hostname::Long;

has 'home_dir' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  builder => '_build_home_dir'
);

sub _build_home_dir { File::HomeDir->my_home } 

has 'cmd_dir' => (
  is      => 'ro',
  isa     => Str,
  lazy    => 1,
  writer  => '_set_cmd_dir', 
  builder => '_build_cmd_dir'
);

sub _build_cmd_dir { shift->home_dir .'/.exc'; }

has 'help' => (
  is       => 'ro',
  isa      => Bool,
  lazy     => 1,
  default  => sub { 0 },
  writer   => '_set_help',
);

sub show_help { shift->help }

has 'global_cmd_data' => (
  is      => 'ro',
  isa     => HashRef,
  lazy    => 1,
  builder => '_build_global_cmd_data'
);

sub _build_global_cmd_data {
  my $self = shift;

  return { map { ( $_ => $self->$_ ) } @{$self->global_attrs} }
}

sub global_attrs {[qw| cmd_dir cmd_cfg cfg_file argv help |]} 

has 'debug' => (
  is        => 'ro',
  isa       => Bool,
  writer    => '_set_debug',
); 

has 'trace' => (
  is        => 'ro',
  isa       => Bool,
  writer    => '_set_trace',
); 

with 'App::RaffiWare::Role::TakesCmdArgs', 
     'App::RaffiWare::Role::HasLogger', 
     'App::RaffiWare::Role::HasCfg';

sub _build_get_opts {[
  qw| 
    cmd-dir=s
    cfg-file=s
    debug
    trace
    help
  |,
]} 

sub _build_pos_args { [] } 

sub print_help {
   my $self = shift;

   print "\n". $self->get_help_data();
   exit(0);
}

sub get_help_data {
  my $self = shift;

  my $class = ref($self);

  my $data_fh = do {
    no strict 'refs';
    *{"${class}::DATA"};
  };

  local $/;
  my $parser = Pod::Text->new( sentence => 1, width => 100); 
  my $ret = '';
  $parser->output_string(\$ret);
  $parser->parse_string_document(<$data_fh>);

  return $ret;
}


sub BUILD { 
  my $self = shift;

  $self->set_level('debug') if $self->debug();
  $self->set_level('trace') if $self->trace();
  $self->logger();

  $self->print_help() if $self->show_help;

  if ($self->needs_init) {

     warn("\nMust run client-init first\n\n");
     exit(1);
  }

  if ( my ($error) = @{$self->arg_errors} )  {

      warn "\n$error\n\n";
      warn $self->get_help_data();
      exit(1); 
  }
}

sub needs_init { !shift->is_initialized() };

sub is_initialized {
  my $self = shift;

  return 0 if !-f $self->cfg_file;

  return 1;
}

1;
