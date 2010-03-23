#!/usr/bin/env perl
use strict;
use warnings;
use CGI;
use HTML::Prototype;
use MIME::Base64;
use Template;

my $query = CGI->new;
   $query->charset("utf-8");

dispatch($query);

sub dispatch {
    my $query = shift;

    if ($query->param('from')) {
        do_convert($query);
    } elsif ($query->param('spinner')) {
        show_spinner($query);
    } else {
        show_form($query);
    }
}

sub do_convert {
    my $query = shift;

    my $from = validate_unit($query->param('from'));
    my $to   = validate_unit($query->param('to'));

    my $func = "convert_${from}_${to}";
    no strict 'refs';
    my $value = eval { $func->(validate_number($query->param('value'))) };
    if ($@) {
        print $query->header, "ERR: Can't do $from to $to conversion: $@";
        return;
    }

    my $format = $value > 0 ? '%.4f' : '%.8f';
    $value = sprintf $format, $value;

    print $query->header, $value;
}

sub validate_unit {
    my $input = shift;
    return ($input =~ /^(\w+)$/)[0];
}

sub validate_number {
    my $input = shift;
    return ($input =~ /^([\-\+\d\.]+)/)[0];
}

sub convert_usd_jpy {
    require Finance::Currency::Convert::Yahoo;
    Finance::Currency::Convert::Yahoo::convert($_[0], 'USD', 'JPY');
}

sub convert_jpy_usd {
    require Finance::Currency::Convert::Yahoo;
    Finance::Currency::Convert::Yahoo::convert($_[0], 'JPY', 'USD');
}

sub convert_inch_meter {
    return 0.0254 * $_[0];
}

sub convert_meter_inch {
    return $_[0] / 0.0254;
}

sub convert_inch_feet {
    return $_[0] / 12;
}

sub convert_feet_inch {
    return $_[0] * 12;
}

sub convert_feet_meter { convert_inch_meter(convert_feet_inch($_[0])) }
sub convert_meter_feet { convert_inch_feet(convert_meter_inch($_[0])) }

sub convert_oz_pound {
    return $_[0] / 16;
}

sub convert_pound_oz {
    return $_[0] * 16;
}

sub convert_g_pound {
    return $_[0] / 453.59237;
}

sub convert_pound_g {
    return $_[0] * 453.59237;
}

sub convert_oz_g { convert_pound_g(convert_oz_pound($_[0])) }
sub convert_g_oz { convert_pound_oz(convert_g_pound($_[0])) }

sub convert_sqf_sqm {
    return $_[0] * 0.09290304;
}

sub convert_sqm_sqf {
    return $_[0] / 0.09290304;
}

sub convert_celsius_fahrenheit {
    (9 / 5) * $_[0] + 32;
}

sub convert_fahrenheit_celsius {
    (5 / 9) * ($_[0] - 32);
}

sub show_form {
    my $query = shift;

    my $tt = Template->new;
    my $template = show_form_template();

    my $stash;
    $stash->{prototype} = HTML::Prototype->new;
    $stash->{cgi}       = $query;

    print $query->header('text/html');
    $tt->process(\$template, $stash);
}

sub show_form_template {
    return <<'TEMPLATE';
[% SET title = "Unit Converter (Japan and United States)" -%]
<html>
<head>
<title>[% title %]</title>
<style>
body,input,td { font-size: 11px; font-family: trebuchet MS }
input { background: #fff }
h1 { font-size: 2em }
h2 { font-size: 1.6em }
</style>
[% prototype.define_javascript_functions %]
<script>
var url = "[% cgi.url %]";
function doConvert(from, to, unit) {
  var spinner = unit + "-spinner";
  $(to).value = ''; // clear
  $(spinner).innerHTML = "<img src=\"[% cgi.url %]?spinner=1\" style=\"vertical-align:middle\" />";
  var query = "value=" + encodeURIComponent($(from).value) + "&from=" + from + "&to=" + to;
  new Ajax.Request(
    url,
    { method: 'get',
      parameters: query,
      onComplete: function(req) { $(to).value = req.responseText; $(spinner).innerHTML = ""; } }
  );
}
</script>
</head>
<body>
<h1>[% title %]</h1>

<h2>Currency</h2>
<p>
<input type="text" size="12" id="usd" onchange="doConvert('usd', 'jpy', 'currency')" /> USD =
<input type="text" size="12" id="jpy" onchange="doConvert('jpy', 'usd', 'currency')" /> JPY
<span id="currency-spinner"></span>
</p>

<h2>Length</h2>
<p>
<input type="text" size="12" id="feet" onchange="doConvert('feet', 'inch', 'length');doConvert('feet', 'meter', 'length')" /> feet =
<input type="text" size="12" id="inch" onchange="doConvert('inch', 'meter', 'length');doConvert('inch', 'feet', 'length')" /> inches =
<input type="text" size="12" id="meter" onchange="doConvert('meter', 'inch', 'length');doConvert('meter', 'feet', 'length')" /> meters
<span id="length-spinner"></span>
</p>

<h2>Weight</h2>
<p>
<input type="text" size="12" id="pound" onchange="doConvert('pound', 'oz', 'weight');doConvert('pound', 'g', 'weight')" /> lb =
<input type="text" size="12" id="oz" onchange="doConvert('oz', 'pound', 'weight');doConvert('oz', 'g', 'weight')" /> oz =
<input type="text" size="12" id="g" onchange="doConvert('g', 'pound', 'weight');doConvert('g', 'oz', 'weight')" /> g
<span id="weight-spinner"></span>
</p>

<h2>Dimensions</h2>
<p>
<input type="text" size="12" id="sqf" onchange="doConvert('sqf', 'sqm', 'dimensions')" /> square feet =
<input type="text" size="12" id="sqm" onchange="doConvert('sqm', 'sqf', 'dimensions')" /> m<sup>2</sup>
<span id="dimensions-spinner"></span>
</p>

<h2>Temperature</h2>
<p>
<input type="text" size="12" id="fahrenheit" onchange="doConvert('fahrenheit', 'celsius', 'temperature')" /> °F = 
<input type="text" size="12" id="celsius" onchange="doConvert('celsius', 'fahrenheit', 'temperature')" /> °C
<span id="temperature-spinner"></span>
</p>



TEMPLATE
}

sub show_spinner {
    my $query = shift;
    print $query->header('image/gif'), decode_base64(<<IMAGE);
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
ISADghsLBDEhIwRfGyMWGA8NXBEAOw==
IMAGE
}
