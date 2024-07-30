# ./script/exc.PL run 
package App::RaffiWare::ExCollect::Worker;

use strict;
use warnings; 

use App::RaffiWare::Logger;

use Moo; 
use Types::Standard qw| :all |;
 
with  'App::RaffiWare::Role::HasCfg',
      'App::RaffiWare::Role::HasLogger', 
      'App::RaffiWare::ExCollect::Role::HasJobs';

has 'cmd_dir' => (
  is       => 'ro',
  isa      => Str,
  required => 1,
); 

sub run {
    my ( $work_type, $job_id, %args ) = @_;

    if ( $work_type eq 'job' ) {
        return run_job($job_id, %args);
    }


}

sub run_job {
    my ( $job_id, %wargs ) = @_; 

    my $debug = delete $wargs{debug};

    my $worker = __PACKAGE__->new(%wargs);

    $worker->set_level('debug') if $debug; 
    $worker->logger();  

    my $job = $worker->load_job($job_id);

    $job->execute();

    return 1;
}



1;
