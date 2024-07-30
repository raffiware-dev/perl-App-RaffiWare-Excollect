#!/usr/bin/perl

# This exists to be packaged as a stand-alone PAR 
# executable that AnyEvent::Fork will use when 
# setting up child processes.
#
# See App::RaffiWare::ExCollect::Cmd::Watcher

use AnyEvent::Fork::Serve;

## installed-lib ##

# skip -M and -e '' arguments
@ARGV = @ARGV[-2,-1];

AnyEvent::Fork::Serve::me;
