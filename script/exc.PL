#!/usr/bin/env perl

use strict;
use warnings;  

use FindBin;

use lib "$FindBin::Bin/../lib"; ## auto-remove ##
use lib "$FindBin::Bin/../local/lib/perl5"; ## auto-remove ## 

## installed-lib ##

use App::RaffiWare::ExCollect::Cmd; 

exit App::RaffiWare::ExCollect::Cmd->run(\@ARGV);
