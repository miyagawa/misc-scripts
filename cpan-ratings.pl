#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use XML::RSS;

my $id = $ARGV[0] or die "Usage: cpan-ratins.pl YOUR-CPAN-ID\n";
my $ua = LWP::UserAgent->new;

my $html = $ua->get("http://search.cpan.org/~$id/")->content;
my @dist = $html =~ m!href="/src/$id/(.*?)-[\d\.]+/">Browse</a>!gi;

for my $dist (@dist) {
    print "[$dist]\n";
    my $url = "http://cpanratings.perl.org/dist/$dist";
    my $xml = $ua->get("$url.rss")->content;
    my $rss = XML::RSS->new;
    eval { $rss->parse($xml) };
    next if $@;

    for my $item (@{$rss->{items}}) {
        my $star = ($item->{description} =~ /Rating: (\d) star/)[0] || 0;
        print( ("*") x $star, (" ") x (5 - $star), " by ", $item->{dc}->{creator}, "\n" );
    }

    if (@{$rss->{items}}) {
        print "  $url\n";
    }
}


