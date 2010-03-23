#!/usr/bin/env perl
use strict;
use warnings;

=head1 DESCRIPTION

This is a simple command-line interface to 30boxes that can be used
like Lifehacker.com's todo.sh script.

=cut

use Date::Manip;
use Encode;
use ExtUtils::MakeMaker ();
use File::HomeDir;
use File::Spec;
use Getopt::Long;
use YAML;
use LWP::UserAgent;
use Pod::Usage;
use URI;
use XML::Simple;

our $conf = File::Spec->catfile(File::HomeDir->my_home, ".30boxes");
our $ua = LWP::UserAgent->new;
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
               "start=s",
               "from=s",
               "end=s",
               "to=s",
               "month=s",
               "date=s",
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

    # map month to start/end
    if ($args{month}) {
        my $target = parse_date($args{month});
        my($year, $month, $day) = split /-/, $target;
        my $end = Date_DaysInMonth($month, $year);
        $args{start} = "$year-$month-1";
        $args{end}   = "$year-$month-$end";
    }

    $args{date} = parse_date($args{date}) if $args{date};

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
    my $time = UnixDate(ParseDateString($_[0]), "%s") or die "Can't parse '$_[0]' as a date string\n";
    my @date = localtime($time);

    return join '-', $date[5] + 1900, $date[4] + 1, $date[3];
}

sub setup_config {
    my $config = eval { YAML::LoadFile($conf) } || {};
    %config = %$config;
    $config{apikey}     ||= prompt("30boxes API Key:");
    $config{auth_token} ||= prompt(<<PROMPT);
You need to login 30boxes to authorize this app.
Go to the following URL and paste the result token here.
  http://30boxes.com/api/api.php?method=user.Authorize&apiKey=$config{apikey}&applicationName=30boxes
Your token:
PROMPT
}

sub save_config {
    YAML::DumpFile($conf, \%config);
    chmod 0600, $conf;
}

sub dow {
    my @dow  = qw(Mon Tue Wed Thu Fri Sat Sun);
    my $date = shift;
    my($y, $m, $d) = split /-/, $date;
    return $dow[ Date_DayOfWeek($m, $d, $y) - 1 ];
}

sub list_events {
    my %param;
    $param{start} = $args{start} if $args{start};
    $param{end}   = $args{end}   if $args{end};
    if ($args{date}) {
        $param{start} = $param{end} = $args{date};
    }

    my $res = call_api("events.Get", %param);

    unless ($res->{eventList}->{event}) {
        print "No event found.\n";
        exit;
    }

    my @events = @{ $res->{eventList}->{event} };
    for my $event (sort { $a->{start} cmp $b->{start} } @events) {
        my($date, $time) = split / /, $event->{start};
        printf "%7s %s (%s) %s (%s)\n",
            $event->{id},
            $date,
            dow($date),
            $event->{summary},
            ($event->{allDayEvent} ? 'All day' : $time),
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
    my $data = XML::Simple::XMLin($res->content, ForceArray => [ 'event', 'tags' ], KeyAttr => undef);
    if ($data->{stat} ne 'ok') {
        my $msg = "call API failed: $data->{err}->{msg} ($data->{err}->{code})\n";
        if ($data->{err}->{code} == 2 || $data->{err}->{code} == 5) {
            $msg .= "You might need to remove $conf to authenticate again.\n";
        }
        die $msg;
    }

    return $data;
}

__END__

=head1 NAME

30boxes.pl - a command-line interface to 30boxes

=head1 SYNOPSIS

  30boxes.pl [options] list
  30boxes.pl add <summary of the event>
  30boxes.pl del <event-id>

    Options:
      --from, --start		Start date of events to search for
      --to, --end		End date of events to search for
      --month			Month of events to search for
      --date                    Date of events to search for

  30boxes.pl list
        List all events in your calendar, starting from today to 90 days later.

  30boxes.pl --from "2 weeks ago" --to today
        List all events in your calendar, starting from 2 weeks ago to today.

  30boxes.pl --month "2006 September"
        List all events in your calendar scheduled on September, 2006.

  30boxes.pl --date tomorrow
        List all events in your calendar tomorrow.

  30boxes.pl add Meeting with Bob tomorrow 3pm
        Add new event titled "Meeting with Bob" on 3pm tomorrow.

  30boxes.pl del 100
        Deletes event with id 100.

=cut
