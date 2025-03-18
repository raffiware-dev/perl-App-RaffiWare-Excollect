#!/usr/bin/env perl

use strict;
use warnings;  


## installed-lib ##

use App::RaffiWare::ExCollect::Cmd; 

exit App::RaffiWare::ExCollect::Cmd->run(\@ARGV);
