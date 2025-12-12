#!/usr/bin/env perl

use strict;
use warnings;  

## installed-lib ##

use AnyEvent::Fork::Early;

$ENV{PATH} = './bin:'. $ENV{PATH}; ## auto-remove ##

use App::RaffiWare::ExCollect::Cmd; 

exit App::RaffiWare::ExCollect::Cmd->run(\@ARGV);
