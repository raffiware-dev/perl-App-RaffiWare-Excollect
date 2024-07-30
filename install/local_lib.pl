#!/usr/bin/env perl

use warnings;
use strict;

BEGIN {
  require local::lib;

  {
    local $0 = '-'; # Hack to make local::lib output shell ENV variables.

    local::lib->import($ARGV[0]);
  }
}

