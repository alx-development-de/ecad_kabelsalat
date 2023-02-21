#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use File::Spec;
use File::Basename;

use ECAD::eplan;
use ECAD::e3series;
use ECAD::EN81346;

use Getopt::Long;
use Config::General qw(ParseConfig);
use Pod::Usage;

use Data::Dumper; # TODO: Remove debug stuff

# Reading the default configuration from the __DATA__ section
# of this script
my $default_config = do {
    local $/;
    <main::DATA>
};
# Loading the file based configuration
our %options = ParseConfig(
    -ConfigFile            => basename($0, qw(.pl .exe .bin)) . '.cfg',
    -ConfigPath            => [ "./", "./etc", "/etc" ],
    -AutoTrue              => 1,
    -MergeDuplicateBlocks  => 1,
    -MergeDuplicateOptions => 1,
    -DefaultConfig         => $default_config,
);

# Processing the command line options
GetOptions(
    'help|?'     => \($options{'run'}{'help'}),
    'man'        => \($options{'run'}{'man'}),
    'loglevel=s' => \($options{'log'}{'level'}),
    'wiring=s'   => \($options{'files'}{'wiring'}),  # Exported wiring list
    'devices=s'  => \($options{'files'}{'devices'}), # Exported device list
    'output=s'   => \($options{'files'}{'output'}),  # If defined, the output is redirected into this file
) or die "Invalid options passed to $0\n";

# Show the help message if '--help' or '--?' if provided as command line parameter
pod2usage(-verbose => 1) if ($options{'run'}{'help'});
pod2usage(-verbose => 2) if ($options{'run'}{'man'});

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($options{'log'}{'level'})));
my $logger = Log::Log4perl::get_logger();

# Postprocessing command line parameters
$options{'files'}{'wiring'} = File::Spec->rel2abs($options{'files'}{'wiring'});
$options{'files'}{'devices'} = File::Spec->rel2abs($options{'files'}{'devices'});
$options{'files'}{'output'} = File::Spec->rel2abs($options{'files'}{'output'}) if (defined $options{'files'}{'output'});

# Checking if the required files are available
if (-f $options{'files'}{'wiring'}) {$logger->debug("Wiring input file [$options{'files'}{'wiring'}]");}
else {$logger->logdie("Wiring input file [$options{'files'}{'wiring'}] not available");}
if (-f $options{'files'}{'devices'}) {$logger->debug("Device input file [$options{'files'}{'devices'}]");}
else {$logger->logdie("Device input file [$options{'files'}{'devices'}] not available");}
if (defined $options{'files'}{'output'}) {$logger->debug("Output file [$options{'files'}{'output'}]");}

$logger->info("Analyzing device list content");
my %device_structure = ECAD::e3series::import_devices($options{'files'}{'devices'});

# Parsing the wiring information list
$logger->info("Parsing the wiring file content from [$options{'files'}{'wiring'}]");
# Calling the import and defining the defaults
print Dumper \%options;
my @connections = ECAD::e3series::import_wiring($options{'files'}{'wiring'}, {
    'color' => $options{'ecad'}{'defaults'}{'color'},
    'gauge' => $options{'ecad'}{'defaults'}{'wire_gauge'}
});
print Dumper \@connections;

__DATA__

<log>
    level=INFO
</log>

<files>
    wiring = "./data/export/wiring.txt"
    devices = "./data/export/devices.txt"
    <target>
        file = "./data/wire_assist_1_2_generated.xlsx"
        table = "ECAD export"
    </target>
</files>