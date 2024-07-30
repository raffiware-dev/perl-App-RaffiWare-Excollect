package App::RaffiWare::ExCollect::Role::HasJobs;

use strict;
use warnings; 

use Moo::Role; 
use Types::Standard qw| :all |;

use App::RaffiWare::ExCollect::Job;
use App::RaffiWare::Cfg;

has 'jobs_dir' => (
  is    => 'ro',
  isa   => Str,
  lazy  => 1,
  builder  => '_build_jobs_dir' 
); 

sub _build_jobs_dir {
  my $self = shift; 

  return sprintf('%s/jobs', $self->cmd_dir ); 
}

has 'jobs' => (
  is      => 'ro',
  isa     => ArrayRef,
  lazy    => 1,
  builder => '_build_jobs',
  clearer => 'clear_jobs'
);

sub _build_jobs {
   my $self = shift;  

   my @jobs;

   opendir( my $jobs_dir, $self->jobs_dir );

   while ( my $job_id_dir = readdir $jobs_dir ) {

       next if !-f $self->jobs_dir . '/' . $job_id_dir .'/state'; 

       push @jobs, $self->load_job($job_id_dir);
   }

   closedir $jobs_dir;

   return \@jobs;
}

sub init_job {
  my ($self, $job_data) = @_; 

   my $job = App::RaffiWare::ExCollect::Job->init( 
               {
                  %{$job_data}{qw| id status priority |},
                  command_string => $job_data->{command_instance}->{command_string},
                  instance_id    => $job_data->{command_instance}->{id},
                  client_name    => $job_data->{host}->{hostname},
                  command => {
                    %{$job_data->{command_instance}->{command}}{qw| id  |}, 
                  },
                  instance => {
                    %{$job_data->{command_instance}}{qw| id created_datetime site signed_by site_user_signature command_string |},
                    execute_type => $job_data->{command_instance}->{attributes}->{execute_type}->{value},
                    script_src   => $job_data->{command_instance}->{attributes}->{script_src}->{value} || '',
                  }
               },
               cfg_file => $self->cfg_file, 
               cmd_cfg  => $self->cmd_cfg,
               cmd_dir  => $self->cmd_dir
             ); 

}

sub load_job {
  my ($self, $job_id, %args) = @_;

  return if !-f sprintf('%s/state', $self->get_job_dir($job_id) ); 

  return App::RaffiWare::ExCollect::Job->new( 
           job_id   => $job_id, 
           cmd_dir  => $self->cmd_dir, 
           cfg_file => $self->cfg_file,
           cmd_cfg  => $self->cmd_cfg,
           %args );
}

sub get_job_dir {
  my ($self, $job_id) = @_; 

  return sprintf('%s/%s', $self->jobs_dir, $job_id); 
}

1;
