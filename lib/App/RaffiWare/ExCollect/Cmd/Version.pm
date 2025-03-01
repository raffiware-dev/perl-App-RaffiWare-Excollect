# ./script/exc.PL version
package App::RaffiWare::ExCollect::Cmd::Version;

use strict;
use warnings; 

use Moo; 
use Types::Standard qw| :all |;

use App::RaffiWare::ExCollect;

with 'App::RaffiWare::Role::IsCmd';

sub needs_init { 0 };  
 

sub run {
  my ( $self ) = @_;

  print "\nVersion: $App::RaffiWare::ExCollect::VERSION\n\n";

  return 0;
}

1;
