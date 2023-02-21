package ECAD::e3series;
use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Logger;

use File::Slurp;
use Encode;

use Data::Dumper;

our $VERSION = '0.1';
$VERSION =~ tr/_//d;

use Exporter 'import';
our @EXPORT = qw(import devices import_wiring); # symbols to export on request

sub import_devices($;) {
    my $sourcefile = shift();
    my $logger = Log::Log4perl->get_logger();

    my %device_structure = ();
    my @device_file_content = File::Slurp::read_file($sourcefile, { 'chomp' => 1, 'binmode' => ':encoding(UTF-16-LE)' });
    # Handling the line end characters correctly
    @device_file_content = map {s/\s*$//;
        $_} @device_file_content;

    # Testing, if the source file is a valid e3.series export.
    # In this case the file ends with a line like this:
    # ***** Created by Zuken E³.series *****
    while (scalar(@device_file_content)) {
        my $line_content = pop(@device_file_content);
        if ($line_content =~ m/^[*]+\s*Created by Zuken E.\.series\s*[*]+/gi) {
            $logger->debug("Seems to be a valid Zuken e3.series source file");
            last;
        }
        $logger->logdie("No valid Zuken e3.series source file found");
    }

    # Getting rid of all lines in the header before the beginning of the file
    while (scalar(@device_file_content)) {
        my $line_content = shift(@device_file_content);
        if ($line_content =~ m/^-+/gi) {
            last;
        }
    }
    # Removing empty lines from content array
    @device_file_content = grep {/\S/} @device_file_content;

    foreach my $line (@device_file_content) {
        # Splitting the content of the csv data
        my $article_number = substr($line, 13, 18);

        # Getting rid of the trailing whitespaces
        $article_number =~ s/\s*$//gi;
        $logger->debug("Article [$article_number] identified, looking for devices");

        my @devices = ();
        @devices = split(/\s*,\s*/, substr($line, 111)) if (length($line) > 111);

        # Exit, if there are no devices assigned, cause in this case the article
        # is not required.
        unless (scalar(@devices)) {
            $logger->warn("[$article_number] is an anonymous article and not assigned to any device");
            next;
        }
        # Removing the trailing counter if the article is assigned
        # multiple times to the device
        foreach (@devices) {s/(\([0-9]+\))?$//;}
        $logger->info("Assigning article [$article_number] to the devices [" . join('],[', @devices) . "]");

        foreach my $device_id (@devices) {
            # Checking device identifier against the EN81346 specification
            $logger->warn("Device identifier [$device_id] is not valid according EN81346")
                unless ECAD::EN81346::is_valid($device_id);
            $device_id = ECAD::EN81346::to_string($device_id); # Normalize the value

            # Getting the device reference, if already known with other articles
            my %device = ();
            if (defined($device_structure{$device_id})) {
                $logger->debug("Device already used, using the reference");
                %device = %{$device_structure{$device_id}};
            }

            unless (defined $device{'MASTER'}) {
                $logger->debug("No master device assigned, using this article [$article_number]");
                $device{'MASTER'} = $article_number;
            }

            my @articles = $device{'ARTICLES'} ? @{$device{'ARTICLES'}} : ();
            push(@articles, $article_number);
            $device{'ARTICLES'} = \@articles;

            $device_structure{$device_id} = \%device;
        }
    }
    return %device_structure;
}

sub import_wiring($$;) {
    my $sourcefile = shift();
    my %default = %{shift()};

    my $logger = Log::Log4perl->get_logger();
    my @connections = ();

    my @wiring_file_content = File::Slurp::read_file($sourcefile, { 'chomp' => 1, 'binmode' => ':encoding(UTF-16-LE)' });
    # Handling the line end characters correctly
    @wiring_file_content = map {s/\s*$//;
        $_} @wiring_file_content;

    # Testing, if the source file is a valid e3.series export.
    # In this case the file ends with a line like this:
    # ***** Created by Zuken E³.series *****
    while (scalar(@wiring_file_content)) {
        my $line_content = pop(@wiring_file_content);
        if ($line_content =~ m/^[*]+\s*Created by Zuken E.\.series\s*[*]+/gi) {
            $logger->debug("Seems to be a valid Zuken e3.series source file");
            last;
        }
        $logger->logdie("No valid Zuken e3.series source file found");
    }

    # Getting rid of all lines in the header before the beginning of the file
    while (scalar(@wiring_file_content)) {
        my $line_content = shift(@wiring_file_content);
        if ($line_content =~ m/^-+/gi) {
            last;
        }
    }
    # Removing empty lines from content array
    @wiring_file_content = grep {/\S/} @wiring_file_content;

    # Parsing the wiring information list
    foreach my $line (@wiring_file_content) {
        # Splitting the content of the csv data
        my @line_content = split(/[;]/, $line);

        my %connection = (
            'source'  => substr($line, 20, 31),
            'target'  => substr($line, 51, 31)
        );

        # Removing the whitespaces in the device id tag
        $connection{'source'} =~ s/\s*//g;
        $connection{'target'} =~ s/\s*//g;

        # In e3.series the device id tags are according the EN81346, but to
        # be sure it will be checked
        $connection{'source'} =~ ECAD::EN81346::to_string($connection{'source'});
        $connection{'target'} =~ ECAD::EN81346::to_string($connection{'target'});

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

        # Checking the additional information
        if(length($line) > 112) {
            $connection{'color'} = uc(encode(':utf-8', substr($line, 112, 10)));
            $connection{'color'} =~ s/\s*//g;
            $logger->debug("Color [$connection{'color'}] detected for the connection");
        } else {
            $logger->debug("Wire color not defined, using default [$default{'color'}]");
            $connection{'color'} = $default{'color'};
        }

        # The wire gauge should be read from the E-CAD export like the wire color and also a default value
        # from the configuration must be applied if nothing else is specified.
        if(length($line) > 122) {
            $logger->debug("Wire gauge definition detected");
            $connection{'wire_gauge'} = encode('utf-8', substr($line, 122, 10));
            $connection{'wire_gauge'} =~ s/\s*//g;
            $connection{'wire_gauge'} =~ s/[^0-9,.]+//g;
        } else {
            $logger->debug("Wire gauge not defined, using default [$default{'gauge'}]mm^2");
            $connection{'wire_gauge'} = $default{'gauge'};
        }

        push(@connections, \%connection);
    }
    return @connections;
}

1;