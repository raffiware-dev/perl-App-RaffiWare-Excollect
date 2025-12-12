package App::RaffiWare::ExCollect::Cmd;

use strict;
use warnings;

use Moo;
use Types::Standard qw| :all |;

use Carp;
use Module::Runtime qw| use_module |;
use File::HomeDir;
use String::CamelCase qw|camelize|;
use Sys::Hostname;
use Try::Tiny; 

with 'App::RaffiWare::Role::IsCmd';

sub needs_init { 0 }; 

my $cmd_to_module = sub {
   my $cmd = shift or return '';

   $cmd =~ s/-/_/g;

   return camelize($cmd);
};

has 'sub_cmd' => (
  is      => 'ro',
  isa     => Str,
  writer  => '_set_sub_cmd'
);  

sub _build_pos_args {
  [
    [ '_set_sub_cmd', 'No Command Set', $cmd_to_module ]
  ]
}

sub run {
  my ( $class, $argv ) = @_;

  my $self = $class->new( argv => $argv );

  if ( $self->debugging_enabled ) {
      $SIG{__DIE__} = sub { ERROR(Carp::longmess(@_)) }; 
  }

  DEBUG('Global Settings');
  DEBUG( sprintf('  %-30s : %s', 'cmd_dir', $self->cmd_dir ) );
  DEBUG( sprintf('  %-30s : %s', 'log_level', $self->log_level ) ); 
  DEBUG( sprintf('  %-30s : %s', 'cfg_file', $self->cfg_file ) ); 
  foreach (qw|
     api_hostname
     api_timeout
     exc_ws_endpoint
  |) {
     DEBUG(sprintf('  %-30s : %s', $_, $self->get_cfg_val($_) ) );
  }

  my $sub_cmd = $self->get_sub_cmd();

  return $sub_cmd->run();
}

sub get_sub_cmd {
  my ( $self ) = @_; 

  my $sub_cmd   = $self->sub_cmd;
  my $cmd_class = ref($self) ."::$sub_cmd"; 

  try { local $SIG{__DIE__}; use_module($cmd_class) } 
  catch {  
     DEBUG("Module load error: $_");
     warn "\nInvalid Command: $sub_cmd\n\n";
     warn $self->get_help_data();
     exit(1);  
  };

  return $cmd_class->new( 
    %{$self->global_cmd_data}, 
    cmd_dir  => $self->cmd_dir,
    cfg_file => $self->cfg_file,
    debug    => $self->debug ); 
}

sub show_help { my $self = shift; $self->help && !$self->sub_cmd }


1;

__DATA__


=head1 SYNOPSIS 

  exc <sub_command> [sub_command_args ... ] [--debug] [--help]

=head1 EXAMPLES

  exc client-init Skvjsd213ASkjvsafdasff
  exc watcher --no-daemonize

=head1 SUB COMMANDS

=over 12

=item client-init

- Initialize and register client.

=item job  

- Execute a specific job.

=item watcher

- Start daemon to automatically fetch and execute new jobs.

=item version

- Print client version

=back 

=head1 OPTIONS

=over 4

=item --cmd-dir [~/.exc]

Base directory for command data.

=item --cfg-file  [~/.exc/exc.cfg]

Client configuration file.

=item --debug

Log debugging information

=item [sub_command] --help

Print this document

=back

=head1 CONFIGURATION

=over 4

=item  ~/.exc/exc.cfg

=back 

=cut 
 
