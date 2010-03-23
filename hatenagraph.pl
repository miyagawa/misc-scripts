#!/usr/bin/env perl
use strict;
use warnings;

=head1 DESCRIPTION

This is a simple command-line interface to Hatena Graph.

=cut

use DateTime;
use Encode;
use ExtUtils::MakeMaker ();
use File::HomeDir;
use File::Spec;
use Getopt::Long;
use YAML;
use LWP::UserAgent;
use Pod::Usage;
use Term::ReadPassword;

our $conf = File::Spec->catfile(File::HomeDir->my_home, ".hatenagraph");
our $ua   = LWP::UserAgent->new;
our %config = ();
our %args   = ();
our $changed;

$ua->env_proxy;

main();

END {
    save_config() if $changed;
}

sub prompt {
    my $value = ExtUtils::MakeMaker::prompt($_[0]);
    $changed++;
    return $value;
}

sub prompt_password {
    my $value = read_password("$_[0]  ");
    $changed++;
    return $value;
}

sub setup_encoding {
    my $encoding;
    eval {
        require Term::Encoding;
        $encoding = Term::Encoding::get_encoding();
    };
    $encoding ||= "utf-8";
    binmode STDOUT, ":encoding($encoding)";
    binmode STDIN, ":encoding($encoding)";
    @ARGV = map decode($encoding, $_), @ARGV;
}

sub main {
    setup_encoding();
    GetOptions(\%args,
               "date=s",
               "help",
               "config=s")
        or pod2usage(2);

    $conf = $args{config} if $args{config};
    pod2usage(0) if $args{help};

    my %commands = (
        update => \&update_graphs,
        setup  => sub { setup_config(1) },
        null   => sub { },
    );

    my $command = shift @ARGV || ($changed ? 'null' : 'update');
    setup_config() unless $command eq 'setup';

    $commands{$command} or pod2usage(-message => "Unknown command: $command", -exitval => 2);
    $commands{$command}->();
}

sub setup_config {
    my $force = shift;
    unless ($force) {
        my $config = eval { YAML::LoadFile($conf) } || {};
        %config = %$config;
    }
    $config{username} ||= prompt("Hatena username:");
    $config{password} ||= prompt_password("Hatena password:");
    $config{graphs}   ||= encode_utf8( prompt("Graph names (comma separated):") );

    $ua->credentials('graph.hatena.ne.jp:80', '', $config{username}, $config{password});
}

sub save_config {
    YAML::DumpFile($conf, \%config);
    chmod 0600, $conf;
}

sub update_graphs {
    $args{date} ||= DateTime->now(time_zone => 'local')->ymd;
    for my $graph (split /,\s*/, $config{graphs}) {
        utf8::decode($graph);
        my $value = ExtUtils::MakeMaker::prompt("$graph on $args{date}:");
        next unless defined $value && $value =~ /\S/;
        utf8::encode($graph);
        my $res = $ua->post( 'http://graph.hatena.ne.jp/api/post', {
            graphname => $graph,
            date      => $args{date},
            value     => $value,
        });
        warn $res->content unless $res->code == 201;
        warn "Data posted.\n"  if $res->code == 201;
    }
}

=head1 NAME

hatenagraph.pl - a command-line interface to Hatena Graph

=head1 SYNOPSIS

  hatenagraph setup
  hatenagraph [options] update
