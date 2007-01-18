#!/usr/bin/perl
use strict;
use warnings;
use WWW::Google::Calculator;

my $expression = join ' ', @ARGV
    or die "Usage: gcal.pl expression\n";

print WWW::Google::Calculator->new->calc($expression), "\n";


