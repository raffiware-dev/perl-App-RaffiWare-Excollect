#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Text::Diff;

BEGIN {
  require App::RaffiWare::ExCollect::Worker;
};

use_ok('App::RaffiWare::Cfg');

done_testing();
