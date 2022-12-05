#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Slurp;
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
    'wiring=s'   => \(my $opt_wiring_reference = './data/wiring-export.txt'),  # Exported wiring list
    'devices=s'  => \(my $opt_device_reference = './data/devices-export.txt'), # Exported device list
    'output=s'   => \(my $opt_output_reference = undef),                       # If defined, the output is redirected into this file
) or die "Invalid options passed to $0\n";

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($log_level)));
my $logger = Log::Log4perl::get_logger();

# Postprocessing command line parameters
$opt_wiring_reference = File::Spec->rel2abs($opt_wiring_reference);
$opt_device_reference = File::Spec->rel2abs($opt_device_reference);
$opt_output_reference = File::Spec->rel2abs($opt_output_reference) if (defined $opt_output_reference);

# Checking if the required files are available
if (-f $opt_wiring_reference) {$logger->debug("Wiring input file [$opt_wiring_reference]");}
else {$logger->logdie("Wiring input file [$opt_wiring_reference] not available");}
if (-f $opt_device_reference) {$logger->debug("Device input file [$opt_device_reference]");}
else {$logger->logdie("Device input file [$opt_device_reference] not available");}
if (defined $opt_output_reference) {$logger->debug("Output file [$opt_output_reference]");}

$logger->debug("Analyzing device list content");
my %device_structure = ();
my @device_file_content = File::Slurp::read_file($opt_device_reference, { 'chomp' => 1 });
foreach my $line (@device_file_content) {
    #chomp($line);
    my ($device, $article_name, $master) = split(/[;]/, $line);

    # Checking device identifier against the EN81346 specification
    $logger->warn("Device identifier [$device] is not valid according EN81346") unless ALX::EN81346::is_valid($device);

    $logger->debug("Parsed line content: [$line] results in DEVICE: [$device] MASTER: [$master] ARTICLES: [$article_name]");
    $device_structure{$device}{'MASTER'} = $master if (defined $master);

    my @articles = split(/,/, $article_name);
    if (scalar(@articles)) {
        $logger->debug("Parsed article structure: [" . join("] [", @articles) . "]");
        $device_structure{$device}{'ARTICLES'} = \@articles;
    }
}

# Building a article list depending on the articles found in the structure
# TODO: Check if the BOM is really required. Seems to be not needed
my %bom = ();
foreach my $device (keys(%device_structure)) {
    foreach my $article (@{$device_structure{$device}{'ARTICLES'}}) {
        $bom{$article}++; # increasing the counter for this article
    }
}
$logger->info(scalar(keys(%bom)), " Different article(s) found in the structure");

# TODO: Remove if not longer required
# print Dumper \%device_structure; # Printing the device structure
# print join(', ', keys(%bom)) . "\n"; # Printing all articles identified

# Parsing the wiring information list
my @wiring_file_content = File::Slurp::read_file($opt_wiring_reference, { 'chomp' => 1 });
foreach my $line (@wiring_file_content) {
    #next unless $line; # skip empty ines
    print "$line\n";
}

