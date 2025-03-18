package App::RaffiWare::Cfg;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |; 

use Config::JSON;
use Config::YAML;
use Fcntl qw|:flock|;

has 'cfg_storage' => (
  is      => 'ro',
  isa     => Str,
  default => sub { 'yaml' }
); 

our %CFG_DEFAUTLS = (
    api_hostname      => 'https://devapi.raffiware.io',
    log_level         => 'info',
    job_poll_interval => 60
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
  builder => '_build_yaml'
);   

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

  open( my $lock_fh, '<', $self->cfg_file ) or die "Can't open config file: $!";

  my $ret = flock($lock_fh, LOCK_EX|LOCK_NB);

  $self->_set_lock($lock_fh) if $ret;

  return $ret;
}

sub unlock {
  my $self = shift; 

  return if !$self->is_locked; 

  flock( $self->_lock, LOCK_UN );
  close $self->_lock;
  $self->_clear_lock;
}

sub _build_yaml {  
  my $self = shift;

  if ( !-f $self->cfg_file ) {
    die "Invalid Config: ". $self->cfg_file if !$self->create;

    open my $cfg_fh, '>',  $self->cfg_file;
    close $cfg_fh;
  }  

  my $c = Config::YAML->new( 
            config => $self->cfg_file,
            ( %{ $self->cfg_data } ) ); 

  return $c;
} 

has 'json' => (
  is      => 'ro',
  isa     => InstanceOf['Config::JSON'],
  lazy    => 1, 
  builder => '_build_json'
); 

sub _build_json {  
  my $self = shift;

  my $json_file = $self->cfg_file;

  if ( !-f $json_file ) {
    die "Invalid Config: ". $self->cfg_file if !$self->create;

    open my $cfg_fh, '>',  $json_file;
    print $cfg_fh '{}';
    close $cfg_fh;
  }

  return Config::JSON->new( pathToFile => $self->cfg_file );
}


sub init {
  my $class = shift; 

  my $self = $class->new(@_);   

  $self->yaml->write;

  return $self;
}

sub set {
  my ( $self, @kvs ) = @_;  

  while ( my $key = shift @kvs ) {

    my $value = shift @kvs;

    if ($self->cfg_storage eq 'json') {
        $self->set_json( $key => $value );
    }
    elsif ($self->cfg_storage eq 'yaml') {
        $self->set_yaml( $key => $value );
    }

  }

  $self->yaml->write() if $self->cfg_storage eq 'yaml';

}

sub set_json {
  my ( $self, $key, $value ) = @_;   

  $self->json->set( $key => $value ) ; 
}

sub set_yaml {
  my ( $self, $key, $value ) = @_;

  if ( ref($key) eq 'ARRAY' 
    and scalar @$key > 1
  ) {
    my $acc  = shift @$key ;
    my $root = $self->get($acc);

    while ( @$key > 1 ) { 
      $root = $root->{ shift @$key } 
    }

    $root->{ shift @$key } = $value;

  }
  else {

    my $acc = "set_$key";

    $self->yaml->$acc($value);
  }

}

sub get {
  my ( $self, $key ) = @_;  

  return $self->json->get($key) if $self->cfg_storage eq 'json';

  my $acc = "get_$key";

  return $self->yaml->$acc;
}

1;
