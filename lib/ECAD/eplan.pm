package ECAD::eplan;
use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Logger;

use File::Slurp;

use Data::Dumper;

our $VERSION = '0.1';
$VERSION =~ tr/_//d;

use Exporter 'import';
our @EXPORT = qw(import devices import_wiring); # symbols to export on request

sub import_devices($;) {
    my $sourcefile = shift();
    my $logger = Log::Log4perl->get_logger();

    my %device_structure = ();
    my @device_file_content = File::Slurp::read_file($sourcefile, { 'chomp' => 1 });
    foreach my $line (@device_file_content) {
        # Splitting the content of the csv data
        my ($device, $article_name, $master) = split(/[;]/, $line);

        # Checking device identifier against the EN81346 specification
        $logger->warn("Device identifier [$device] is not valid according EN81346") unless ECAD::EN81346::is_valid($device);
        $device = ECAD::EN81346::to_string($device); # Normalize the value
        $logger->debug("Parsed line content: [$line] results in DEVICE: [$device] MASTER: [$master] ARTICLES: [$article_name]");
        $device_structure{$device}{'MASTER'} = $master if (defined $master);

        my @articles = split(/,/, $article_name);
        if (scalar(@articles)) {
            $logger->debug("Parsed article structure: [" . join("] [", @articles) . "]");
            $device_structure{$device}{'ARTICLES'} = \@articles;
        }
    }

    return %device_structure;
}

sub import_wiring($$;) {
    my $sourcefile = shift();
    my %default = %{shift()};

    print Dumper \%default;

    my $logger = Log::Log4perl->get_logger();

    my @connections = ();

    # Parsing the wiring information list
    my @wiring_file_content = File::Slurp::read_file($sourcefile, { 'chomp' => 1 });
    foreach my $line (@wiring_file_content) {
        # Splitting the content of the csv data
        my @line_content = split(/[;]/, $line);

        my %connection = (
            'source'  => ECAD::EN81346::to_string($line_content[0]),
            'target'  => ECAD::EN81346::to_string($line_content[1]),
            'comment' => $line_content[6],
            #    'length'          => $line_content[5] ? $line_content[5] : '0,001m',
        );

        $logger->debug("Inspection connection [$connection{'source'} <-> $connection{'target'}]");
        unless ($connection{'source'} && $connection{'target'}) {
            $logger->warn("Target and/or source connections are invalid, skipping processing connection");
            next;
        }

        # Skipping further processing, if the wiring is a cable connection
        if (ECAD::EN81346::to_string($line_content[2])) {
            $logger->debug("Cable [" . ECAD::EN81346::to_string($line_content[2]) .
                "] detected, skipping further wire processing");
            next;
        }

        # Implementing the color mapping, cause the color definition strings from
        # the E-CAD may differ to the required test in the wire assist.
        if (defined $line_content[3]) {
            $connection{'color'} = uc($line_content[3]);
            $logger->debug("Color [$connection{'color'}] detected for the connection");
        }
        else {
            $logger->debug("Wire color not defined, using default [$default{'color'}]");
            $connection{'color'} = $default{'color'};
        }

        # The wire gauge should be read from the E-CAD export like the wire color and also a default value
        # from the configuration must be applied if nothing else is specified.
        if ($line_content[4]) {
            $logger->debug("Inspecting wire gauge definition [$line_content[4]]");
            $connection{'wire_gauge'} = $line_content[4];
            $connection{'wire_gauge'} =~ s/([0-9,.]+).*/$1/gi; # Extracting just the number
            $logger->debug("Wire gauge [$connection{'wire_gauge'}] detected for the connection");
        }
        else {
            $logger->debug("Wire gauge not defined, using default [$default{'gauge'}]mm^2");
            $connection{'wire_gauge'} = $default{'gauge'};
        }

        push(@connections, \%connection);
    }
    return @connections;
}

1;
