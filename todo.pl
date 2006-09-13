#!/usr/bin/env perl
use strict;
use warnings;

=head1 DESCRIPTION

This is a simple command-line interface to Hiveminder that loosely
emulates the interface of Lifehacker.com's todo.sh script.

=cut

use YAML ();
use XML::Simple;
use LWP::UserAgent;
use Number::RecordLocator;
use Getopt::Long;
use Pod::Usage;
use Fcntl qw(:mode);

our $CONFFILE = "$ENV{HOME}/.hiveminder";
our %config = ();
our $ua = LWP::UserAgent->new;
our $locator = Number::RecordLocator->new();
our $default_query = "not/complete/owner/me/starts/before/tomorrow/accepted/but_first/nothing";
our %args;

$ua->cookie_jar({});

main();

sub main {
    setup_config();
    setup_term_encoding();

    GetOptions(\%args, "tags=s", "tag=s@", "group=s") or pod2usage(2);
    
    push @{$args{tag}}, split /\s+/, $args{tags} if $args{tags};

    do_login() or die("Bad username/password -- edit $CONFFILE and try again.");

    my %commands = (
        list    => \&list_tasks,
        add     => \&add_task,
        do      => \&do_task,
        done    => \&do_task,
        del     => \&del_task,
        rm      => \&del_task,
       );
    
    my $command = shift @ARGV || "list";
    $commands{$command} or pod2usage(-message => "Unknown command: $command", -exitval => 2);

    $commands{$command}->();
}


=head1 CONFIG FILE

These methods deal with loading the config file, and populating it
with selections read from the terminal on our first run.

=cut

sub setup_config {
    check_config_perms() unless($^O eq 'win32');
    load_config();
    check_config();

}

sub check_config_perms {
    return unless -e $CONFFILE;
    my @stat = stat($CONFFILE);
    my $mode = $stat[2];
    if($mode & S_IRGRP || $mode & S_IROTH) {
        warn("Config file $CONFFILE is readable by someone other than you, fixing.");
        chmod 0600, $CONFFILE;
    }
}

sub load_config {
    return unless(-e $CONFFILE);
    %config = %{YAML::LoadFile($CONFFILE)};
}

sub check_config {
    new_config() unless $config{email};
}

sub new_config {
    print <<"END_WELCOME";
Welcome to todo.pl! before we get started, please enter your
hiveminder username and password so we can access your tasklist.

This information will be stored in $CONFFILE, should you ever need to
change it.

END_WELCOME

    $config{site} ||= 'http://hiveminder.com';

    while (1) {
        print "First, what's your email address? ";
        $config{email} = <stdin>;
        chomp($config{email});

        use Term::ReadKey;
        print "And your password? ";
        ReadMode('noecho');
        $config{password} = <stdin>;
        chomp($config{password});
        ReadMode('restore');

        last if do_login();
        print "That combination doesn't seem to be correct. Try again?\n";
    }

    YAML::DumpFile($CONFFILE, \%config);
    chmod 0600, $CONFFILE;
}

sub setup_term_encoding {
    my $encoding;
    eval {
        require Term::Encoding;
        $encoding = Term::Encoding::get_encoding();
    };
    $encoding ||= "utf-8";
    binmode STDOUT, ":encoding($encoding)";
}

=head1 TASKS

methods related to manipulating tasks -- the meat of the script.

=cut

sub list_tasks {
    my $query = $default_query;

    my $tag;
    $query .= "/tag/$tag" while $tag = shift @{$args{tag}};
    $query .= "/group/" . $args{group} if $args{group};

    my $tasks = download_tasks($query);
    
    for my $t (@$tasks) {
        printf "%4s :", $locator->encode($t->{id});
        print '(' . chr(ord('A') + 5 - $t->{priority}) . ') ';
        print $t->{summary};
        if($t->{tags}) {
            print ' [' . $t->{tags} . ']';
        }

        if($t->{group}) {
            print ' (' . $t->{group} . ')';
        }
        
        print "\n";
    }
}

sub do_task {
    my $task = shift @ARGV or pod2usage(-message => 'Need a task-id!');
    my $id = $locator->decode($task) or die("Invalid task ID: $task");
    my $result = call(UpdateTask =>
                      id         => $id,
                      complete   => 1);
    if($result->{result}{success} == 1) {
        print "Task $task completed.\n";
    } else {
        die(YAML::Dump($result));
    }
}

sub add_task {
    my $summary = join(" ",@ARGV) or pod2usage(-message => "Must specify a task description");
    my %task;
    $task{tags} = join(" ", map {'"' . $_ . '"'} @{$args{tag}}) if $args{tag};
    $task{group_id} = $args{group} if $args{group};
    $task{summary} = $summary;
    $task{owner_id} = $config{email};

    my $result = call(CreateTask => %task);
    if($result->{result}{success} == 1) {
        print "Task created.\n";
    } else {
        die(YAML::Dump($result));
    }
}

sub del_task {
    my $task = shift @ARGV or pod2usage(-message => 'Need a task-id!');
    my $id = $locator->decode($task) or die("Invalid task ID: $task");
    my $result = call(DeleteTask => id => $id);
    if($result->{result}{success} == 1) {
        print "Deleted task.\n";
    } else {
        die YAML::Dump($result);
    }
                      
}


=head1 BTDT API

These functions deal with calling the BTDT/Jifty api to communicate
with the server.

=cut

sub do_login {
    my $result = call(Login =>
                      address  => $config{email},
                      password => $config{password});
    return $result->{result}{success} == 1;
}

sub download_tasks {
    my $query = shift || $default_query;

    my $result = call(DownloadTasks =>
                      query  => $query,
                      format => 'yaml');
    return YAML::Load($result->{result}{content}{result});
}

sub call ($@) {
    my $class   = shift;
    my %args    = (@_);
    my $moniker = 'fnord';

    my $res = $ua->post(
        $config{site} . "/__jifty/webservices/xml",
        {   "J:A-$moniker" => $class,
            map { ( "J:A:F-$_-$moniker" => $args{$_} ) } keys %args
        }
    );

    if ( $res->is_success ) {
        return XML::Simple::XMLin($res->content);
    } else {
        die $res->status_line;
    }
}

__END__

=head1 NAME

todo.pl - a command-line interface to Hiveminder

=cut

=head1 SYNOPSIS

  todo.pl [options] list
  todo.pl [options] add <summary>
  todo.pl done <task-id>
  todo.pl del|rm <task-id>

    Options:
       --group                          Operate on tasks in a group
       --tag                            Operate on tasks with a given tag

  todo.pl list
        List all tasks in your todo list.

  todo.pl --tag home --tag othertag --group personal list
        List all personl tasks (not in a group with tags 'home' and 'othertag'.

  


=head1 OPTIONS

=over

=back

=cut

=cut

