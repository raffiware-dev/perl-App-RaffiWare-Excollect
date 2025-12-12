package App::RaffiWare::Cfg;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |; 

use Config::JSON;
use Config::YAML;
use Fcntl qw|:flock|;
use Try::Tiny;

has 'cfg_storage' => (
  is      => 'ro',
  isa     => Str,
  default => sub { 'yaml' }
); 

our %CFG_DEFAUTLS = (
  api_hostname          => 'https://devapi.raffiware.io',
  api_timeout           => 15 ,
  exc_ws_endpoint       => 'wss://devapi.raffiware.io/excollect/ws',
  log_level             => 'info',
  job_poll_interval     => 120,
  timer_check_interval  => 120,
  replay_check_interval => 300,
  ws_ping_interval      => 240,
  max_startup_delay     => 60, 
  max_workers           => 2
); 

sub cfg_defaults {%CFG_DEFAUTLS}

has 'cfg_data' => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} }
); 

has 'cfg_file' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

has 'create' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 1 }
); 

has 'yaml' => (
  is      => 'ro',
  isa     => InstanceOf['Config::YAML'],
  lazy    => 1, 
  clearer => 'clear_yaml',
  builder => '_build_yaml'
);

sub _build_yaml {
  my $self = shift;

  if ( !-f $self->cfg_file ) {
    die "Invalid Config: ". $self->cfg_file if !$self->create;

    open my $cfg_fh, '>',  $self->cfg_file or die "Can't open config file: $!";
    close $cfg_fh;
  }

  my $c = Config::YAML->new(
    config => $self->cfg_file,
    ( %{ $self->cfg_data } ) 
  );

  return $c;
} 

has 'json' => (
  is      => 'ro',
  isa     => InstanceOf['Config::JSON'],
  lazy    => 1, 
  clearer => 'clear_json',
  builder => '_build_json'
); 

sub _build_json {  
  my $self = shift;

  my $json_file = $self->cfg_file;

  if ( !-f $json_file ) {
    die "Invalid Config: ". $self->cfg_file if !$self->create;

    open my $cfg_fh, '>',  $json_file or die "Can't open config file: $!";
    print $cfg_fh '{}';
    close $cfg_fh;
  }

  return Config::JSON->new( pathToFile => $self->cfg_file );
}

has '_lock' => (
  is        => 'ro',
  isa       => FileHandle,
  writer    => '_set_lock',
  clearer   => '_clear_lock',
  predicate => 'is_locked'
); 

sub lock {
  my $self = shift;

  return 1 if $self->is_locked;

  return try {

    open( my $lock_fh, '<', $self->cfg_file ) or die "Can't open config file: $!"; 

    local $SIG{ALRM} = sub { die "lock timeout\n" };

    alarm 1;
    my $ret = flock($lock_fh, LOCK_EX);
    alarm 0;

    return if !$ret;

    $self->clear_json if $self->cfg_storage eq 'json';
    $self->clear_yaml if $self->cfg_storage eq 'yaml'; 

    $self->_set_lock($lock_fh);

    return $ret; 
  }
  catch {
    warn($_);
    return
  };
}

sub unlock {
  my $self = shift; 

  return if !$self->is_locked; 

  flock( $self->_lock, LOCK_UN );
  close $self->_lock;
  $self->_clear_lock;
}  

sub BUILD {
  my ( $self ) = @_; 

  # Force config data to load immediately so we can test 
  # if it's valid.
  try {
    $self->json if $self->cfg_storage eq 'json';
    $self->yaml if $self->cfg_storage eq 'yaml';
  }
  catch {
    die(sprintf("Config file %s failed to load with error: $_", $self->cfg_file));
  };
}

sub set {
  my ( $self, @kvs ) = @_;

  while ( my $key = shift @kvs ) {

    my $value = shift @kvs;

    if ($self->cfg_storage eq 'json') {

      $self->json->set( $key => $value );
    }
    elsif ($self->cfg_storage eq 'yaml') {
      my $acc = "set_$key";

      $self->yaml->$acc($value); 
    }
  }

  $self->yaml->write() if $self->cfg_storage eq 'yaml';
}

sub delete {
  my ( $self, @kvs ) = @_;

  while ( my $key_id = shift @kvs ) {

    if ($self->cfg_storage eq 'json') {
      $self->json->delete($key_id) ;
    }
    elsif ($self->cfg_storage eq 'yaml') {
      delete $self->yaml->{$key_id};
    }
  }

  $self->yaml->write() if $self->cfg_storage eq 'yaml';
}

sub get {
  my ( $self, $key ) = @_;

  my $ret = ( $self->cfg_storage eq 'json' ? $self->json->get($key) :
              do { my $acc = "get_$key"; $self->yaml->$acc; }
            ) // $CFG_DEFAUTLS{$key};

  return $ret;
}

sub data {
  my ( $self ) = @_;

  if ($self->cfg_storage eq 'json') {
    return $self->json->config;
  }
  elsif ($self->cfg_storage eq 'yaml') {
    return { %{$self->yaml } }; 
  }
}

sub exists {
  my ( $self, $key ) = @_;

  if ($self->cfg_storage eq 'json') {
    return exists $self->json->config->{$key};
  }
  elsif ($self->cfg_storage eq 'yaml') {
    return exists { %{$self->yaml } }->{$key}; 
  }
}   

1;
