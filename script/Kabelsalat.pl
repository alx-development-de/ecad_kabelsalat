#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Basename;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use ALX::EN81346;

use Getopt::Long;

use Data::Dumper; # TODO: Remove debug stuff

# Processing the command line options
GetOptions(
    'loglevel=s' => \(my $log_level = 'INFO'),
    'wiring=s'      => \(my $opt_wiring_reference = './data/wiring-export.txt'), # Exported wiring list
    'devices=s'      => \(my $opt_device_reference = './data/devices-export.txt'), # Exported device list
    'output=s'      => \(my $opt_output_reference = undef), # If defined, the output is redirected into this file
) or die "Invalid options passed to $0\n";

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($log_level)));
my $logger = Log::Log4perl->get_logger();

# Postprocessing command line parameters
$opt_wiring_reference = File::Spec->rel2abs($opt_wiring_reference);
$opt_device_reference = File::Spec->rel2abs($opt_device_reference);
$opt_output_reference = File::Spec->rel2abs($opt_output_reference) if defined $opt_output_reference;

$logger->debug("Wiring input file [$opt_wiring_reference]") if -f $opt_wiring_reference;
$logger->debug("Device input file [$opt_device_reference]") if -f $opt_device_reference;
$logger->debug("Output file [$opt_output_reference]") if defined $opt_output_reference;

# Parsing the device information list
open(DEVICES, '<'.$opt_device_reference)or $logger->logdie("Failed to open wiring file [$opt_device_reference]");
my @device_file_content = <DEVICES>;
close(DEVICES);

my %device_structure = ();
$logger->debug("Analyzing device list content");
foreach my $line (@device_file_content) {
    chomp($line);
    my ($device, $articlestring, $master) = split(/[;]/, $line);

    # Checking device identifier against the EN81346 specification
    $logger->warn("Device identifier [$device] is not valid according EN81346") unless ALX::EN81346::is_valid($device);

    $logger->debug("Parsed line content: [$line] results in DEVICE: [$device] MASTER: [$master] ARTICLES: [$articlestring]");
    $device_structure{$device}{'MASTER'} = $master if($master);

    my @articles = split(/,/, $articlestring);
    if(scalar(@articles)) {
        $logger->debug("Parsed article structure: [".join("] [", @articles)."]");
        $device_structure{$device}{'ARTICLES'} = \@articles;
    }
}

# A Device structure has been build from file
print Dumper \%device_structure;

# Building a article list depending on the articles found in the structure
my %bom = ();
foreach my $device (keys(%device_structure)) {
    foreach my $article ( @{$device_structure{$device}{'ARTICLES'}} ) {
        $bom{$article}++; # increasing the counter for this article
    }
}
$logger->info(scalar(keys(%bom)), " Different article(s) found in the structure");
print join(', ', keys(%bom))."\n";

# Parsing the wiring information list
open(WIRING, '<'.$opt_wiring_reference)or $logger->logdie("Failed to open wiring file [$opt_wiring_reference]");
my @wiring_file_content = <WIRING>;
close(WIRING);

foreach my $line (@wiring_file_content) {
    chomp($line);
    next unless $line; # skip empty ines
#    print "$line\n";
}

