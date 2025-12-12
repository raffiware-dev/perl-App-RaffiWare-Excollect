# ./script/exc.PL job 
package App::RaffiWare::ExCollect::Cmd::Job;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |;

use App::RaffiWare::Logger;

use AnyEvent;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;
use Data::Dumper;
use JSON qw| decode_json encode_json |; 

with 'App::RaffiWare::Role::IsCmd',
     'App::RaffiWare::Role::HasAPIClient',
     'App::RaffiWare::ExCollect::Role::HasJobs';  

has '+api_class' => (
  default => sub {'App::RaffiWare::ExCollect::API'}
);


has 'do_fetch' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_fetch'
); 

has 'do_execute' => (
  is      => 'ro',
  isa     => Bool,
  default => sub { 0 },
  writer  => '_set_execute'
);

sub _build_get_opts {
  [qw| 
       fetch 
       execute 
  |]
}

has 'job_id' => (
  is      => 'ro',
  isa     => Str,
  writer  => '_set_job_id'
); 

sub _build_pos_args {
  [
    [ '_set_job_id', 'Job Id required', sub { shift } ]
  ]
}

sub run {
  my ( $self ) = @_;

  my $job_id = $self->job_id;

  my $job = $self->load_job( $job_id );

  if ( $self->do_fetch && !$job ) {

    INFO(sprintf('Fetching Job %s data', $job_id ));

    my $job_msg = $self->api->get_job($job_id)
       or FATAL("Could not load job");

    $job = $self->init_job($job_msg->{data}); 
  }
  elsif ($self->do_fetch) {
    WARNING("Job already fetched");
  }
  elsif ( !$job ) {
    FATAL("Job not found");
  }

  $job->execute() if $self->do_execute();

  return 0;
}
 
1; 

__DATA__

=head1 SYNOPSIS

exc job  <job_id>  [--fetch] [--execute] 

=head1 EXAMPLE
 
  exc job chj_AsddASDh234fasdfhadfshsaf

=head1 ARGUMENTS

=over 4

=item <job_id>  - Job Id 

=back 

=head1 OPTIONS

=over 4

=item --fetch - fetch Job information from API

=item --execute - Execute job 

=item --help - Print this document

=back

=cut 
