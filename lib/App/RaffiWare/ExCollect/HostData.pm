package App::RaffiWare::ExCollect::HostData;

use strict;
use warnings;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw| :all |;   

use RaffiWare::APIUtils qw| get_utc_time_stamp get_utc_datetime 
                            get_timestamp_iso8601 make_uri_uuid |; 

use App::RaffiWare::Logger;
use App::RaffiWare::Cfg;

use Net::Domain qw|hostfqdn|;
use Sys::OsRelease;

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

with 'App::RaffiWare::Role::HasLogger';

has 'data_cfg_dir' => (
  is    => 'ro',
  isa   => Str,
  lazy  => 1,
  builder  => '_build_data_cfg_dir' 
); 

sub _build_data_cfg_dir {
  my $self = shift; 

  return sprintf('%s/host_data_cfgs', $self->cmd_dir ); 
}


has 'data_cfgs' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  builder => '_build_data_cfgs',
  clearer => 'clear_data_cfgs'
);

sub _build_data_cfgs {
   my $self = shift;  

   my @cfgs;

   opendir( my $cfgs_dir, $self->data_cfg_dir );

   while ( my $data_cfg = readdir $cfgs_dir ) {

       push @cfgs, $self->load_cfg($data_cfg);
   }

   closedir $cfgs_dir;

   return \@cfgs;
}  

sub load_cfg {
  my ($self, $data_cfg) = @_;

  my $cfg_file =  sprintf('%s/%s', $self->data_cfg_dir, $data_cfg );

  return App::RaffiWare::Cfg->new( cfg_file => $cfg_file );
}

sub data {
   my $self = shift;

   return [@{$self->static_data}, @{$self->dynamic_data}];
}

sub clear_data { my $self = shift; $self->_clear_static_data; $self->_clear_data_map }

has 'static_data' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  builder => '_build_static_data',
  clearer => '_clear_static_data'
);

sub _build_static_data {
   my $self = shift;

   Sys::OsRelease->init();

   my $data = [
        { name        => 'Hostname',
          description => 'Client systme FQDN',
          value_type  => 'text',
          value       => hostfqdn(),
        },
        { name        => 'OperatingSystem',
          description => 'Operating System',
          value_type  => 'text', 
          value       =>  Sys::OsRelease->id()  || 'Unknown'
        }, 
        { name        => 'OperatingSystemVersion',
          description => 'Operating System Version',
          value_type  => 'text', 
          value       => Sys::OsRelease->version_id() || 'Unknown'
        } 
   ];

   # TODO load custom data attibutes.
   #foreach my $data_cfg (@{$self->data_cfgs}) {

   #}

   return $data;
}

sub dynamic_data {

    return [
        { name         => 'Uptime',
          description  => 'Client system uptime',
          value_type   => 'text', 
          value        => `uptime -p`
        },
   ];

}

has 'data_map' => (
  is          => 'ro',
  isa         => HashRef,
  lazy        => 1,
  builder     => '_build_data_map',
  clearer     => '_clear_data_map',
  handles_via => 'Hash',
  handles => {
    get_data => 'get',
  }
);

sub _build_data_map {
   my $self = shift;    

   return {
      map { 
         ( $_->{name} => $_->{value} ) 
      }
      (@{$self->static_data}, @{$self->dynamic_data})
   }

}

1;
