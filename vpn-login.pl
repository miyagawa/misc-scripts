#!/usr/bin/env perl
use strict;
use WWW::Mechanize;
use Crypt::CBC;
use MIME::Base64;
use Term::ReadPassword;
use Try::Tiny;
use YAML;

my $conf_file = "$ENV{HOME}/.vpnloginrc";

my $mech = WWW::Mechanize->new;
$mech->get("https://172.16.129.254:8081/vpn/loginformWebAuth.html");

$mech->dump_forms;

$mech->submit_form(
    form_number => 1,
    fields => {
        userid => $ENV{USER},
        password => get_password(),
    },
);

warn $mech->content =~ /Succeeded/ ? "OK" : "NG";

sub get_password {
    my $key  = read_password('key: ');
    my $cipher = Crypt::CBC->new(-key => $key, -cipher => 'Blowfish');

    my $conf = try { YAML::LoadFile($conf_file) };
    unless ($conf) {
        warn "Config file not found. Setting the password.\n";
        my $new_password = read_password('password: ');
        if ($new_password) {
            YAML::DumpFile($conf_file, { password => encode_base64($cipher->encrypt($new_password)) });
            die "Config file saved. run me again.\n";
        }
        die "Bad password";
    }

    $cipher->decrypt(decode_base64($conf->{password}));
}

