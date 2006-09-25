#!/usr/bin/perl
use strict;
use warnings;

=head1 DESCRIPTION

This is a simple command-line interface to 30boxes that can be used
like Lifehacker.com's todo.sh script.

=cut

use Date::Manip;
use Encode;
use ExtUtils::MakeMaker ();
use Getopt::Long;
use YAML;
use LWP::UserAgent;
use Pod::Usage;
use URI;
use XML::Simple;

our $conf = "$ENV{HOME}/.30boxes";
our $ua = LWP::UserAgent->new;
our %config = ();
our %args   = ();
our $changed;

$ua->env_proxy;

my $encoding;
eval {
    require Term::Encoding;
    $encoding = Term::Encoding::get_encoding();
};
$encoding ||= "utf-8";
binmode STDOUT, ":encoding($encoding)";
binmode STDIN, ":encoding($encoding)";

main();

END {
    save_config() if $changed;
}

sub prompt {
    my $value = ExtUtils::MakeMaker::prompt($_[0]);
    $changed++;
    return $value;
}

sub main {
    GetOptions(\%args,
               "start=s",
               "from=s",
               "end=s",
               "to=s",
               "help",
               "config=s")
        or pod2usage(2);

    $conf = $args{config} if $args{config};
    pod2usage(0) if $args{help};

    # alias from/start, to/end
    $args{start} ||= $args{from};
    $args{end}   ||= $args{to};

    # Human readable one
    $args{start} = parse_date($args{start}) if $args{start};
    $args{end}   = parse_date($args{end})   if $args{end};

    setup_config();

    my %commands = (
        list => \&list_events,
        add  => \&add_event,
        del  => \&delete_event,
        rm   => \&delete_event,
#        update => \&update_event,
    );

    my $command = shift @ARGV || "list";
    $commands{$command} or pod2usage(-message => "Unknown command: $command", -exitval => 2);
    $commands{$command}->();
}

sub parse_date {
    my @date = localtime(UnixDate(ParseDateString(shift), "%s"));
    return join '-', $date[5] + 1900, $date[4] + 1, $date[3];
}

sub setup_config {
    my $config = eval { YAML::LoadFile($conf) } || {};
    %config = %$config;
    $config{apikey}     ||= prompt("30boxes API Key:");
    $config{auth_token} ||= prompt(<<PROMPT);
You need to login 30boxes to authorize this app.
Go to the following URL and paste the result token here.
  http://30boxes.com/api/api.php?method=user.Authorize&apiKey=$config{apikey}&applicationName=cal.pl
Your token:
PROMPT
}

sub save_config {
    YAML::DumpFile($conf, \%config);
}

sub check_stat {
    my $res = shift;
}

sub list_events {
    my $res = call_api("events.Get",
                       $args{start} ? (start => $args{start}) : (),
                       $args{end}   ? (end => $args{end}) : ());

    my @events = @{ $res->{eventList}->{event} };
    for my $event (sort { $a->{start} cmp $b->{start} } @events) {
        printf "%8s %s %s\n", $event->{id}, $event->{start}, $event->{summary};
    }
}

sub add_event {
    my $summary = join ' ', @ARGV;
    my $res = call_api("events.AddByOneBox", event => encode_utf8($summary));

    print "Event ", $res->{eventList}->{event}->[0]->{id}, " created.\n";
}

sub delete_event {
    for my $id (@ARGV) {
        my $res = call_api("events.Delete", eventId => $id);
        print "Event $id deleted.\n";
    }
}

sub update_event {
    my $id = shift @ARGV;
    my $summary = join ' ', @ARGV;
    # XXX this breaks other datetime fields than summary
    my $res = call_api("events.Update", eventId => $id, summary => $summary);
    print "Event $id updated.\n";
}

sub call_api {
    my($method, %opt) = @_;

    my $url = URI->new("http://30boxes.com/api/api.php");
    $url->query_form(
        method => $method,
        apiKey => $config{apikey},
        authorizedUserToken => $config{auth_token},
        %opt,
    );

    my $res  = $ua->get($url);
    my $data = XML::Simple::XMLin($res->content, ForceArray => [ 'event' ], KeyAttr => undef);
    if ($data->{stat} ne 'ok') {
        die "call API failed. You might need to remove $conf to redo the authentication.";
    }

    return $data;
}

__END__

=head1 NAME

cal.pl - a command-line interface to 30boxes

=head1 SYNOPSIS

  cal.pl [options] list
  cal.pl add <text try of the event>
  cal.pl del <event-id>

  cal.pl list
        List all events in your calendar, starting from today to 90 days later.

  cal.pl --from "2 weeks ago" --to today
        List all events in your calendar, starting from 2 weeks ago to today.

  cal.pl add Meeting with Bob tomorrow 3pm
        Add new event titled "Meeting with Bob" on 3pm tomorrow.

  cal.pl del 100
        Deletes event with id 100.

=cut
