#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Slurp;
use File::Basename;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Encode qw(decode encode);
use Excel::Writer::XLSX;

use ALX::EN81346;

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
my %options = ParseConfig(
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
    'wiring=s'   => \($options{'files'}{'wiring'} = './data/wiring-export.txt'),   # Exported wiring list
    'devices=s'  => \($options{'files'}{'devices'} = './data/devices-export.txt'), # Exported device list
    'output=s'   => \($options{'files'}{'output'} = undef),                        # If defined, the output is redirected into this file
) or die "Invalid options passed to $0\n";

# Show the help message if '--help' or '--?' if provided as command line parameter
pod2usage(-verbose => 1) if ($options{'run'}{'help'});
pod2usage(-verbose => 2) if ($options{'run'}{'man'});

=head1 NAME

Kabelsalat - Will help you getting structure information from several E-CAD list exports and
combine them to a base for worker assistance systems.

=head1 SYNOPSIS

C<Kabelsalat> F<[options]>

 Options:
   --help                  Shows a brief help message
   --man                   Prints the full documentation
   --loglevel=[VALUE]      Defines the level for messages
   --wiring=[FILE]         Specifies the input file containing the wiring list
   --devices=[FILE]        Specifies the CSV data source for device article mapping

=head1 OPTIONS

=over 4

=item B<--help>

Prints a brief help message containing the synopsis and a few more
information about usage and exists.

=item B<--man>

Prints the complete manual page and exits.

=item B<--loglevel>=I<[VALUE]>

To adjust the level for the logging messages the desired level may be defined
with this option. Valid values are:

=over 4

=item I<FATAL>

One or more key business functionalities are not working and the whole system does not fulfill
the business functionalities.

=item I<ERROR>

One or more functionalities are not working, preventing some functionalities from working correctly.

=item I<WARN>

Unexpected behavior happened inside the application, but it is continuing its work and the key
business features are operating as expected.

=item I<INFO>

An event happened, the event is purely informative and can be ignored during normal operations.

=item I<DEBUG>

A log level used for events considered to be useful during software debugging when more granular
information is needed.

=item I<TRACE>

A log level describing events showing step by step execution of your code that can be ignored
during the standard operation, but may be useful during extended debugging sessions.

=back

=item B<--wiring>=I<[FILE]>

Specifies the input file containing the wiring list as CSV data source.

B<Example:>
C<=010+INT-E6:PE;=010+INT-X:PE;=010-0100W6;GNYE;1,5 mm²;3 m;>

=item B<--devices>=I<[FILE]>

Specifies the CSV data source for device article mapping. The file is formatted
as: [DEVICE IDENTIFIER];[COMMA SEPARATED LIST OF ARTICLES];[MAIN ARTICLE]

B<Example:>
C<=010+INT-F1;PXC.0800886,PXC.1004348;PXC.0800886>

The main article in the third column is used to specify an article which is used as
a kind of main part for the device. For example a relay and additional contacts. In
this case the main article is the relay and the articles containing additional contacts
as extension to the basic relay is only listed in the second column as article.

=back

=cut

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

$logger->debug("Analyzing device list content");
my %device_structure = ();
my @device_file_content = File::Slurp::read_file($options{'files'}{'devices'}, { 'chomp' => 1 });
foreach my $line (@device_file_content) {
    # Splitting the content of the csv data
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
my @connections = ();
$logger->info("Parsing the wiring file content from [$options{'files'}{'wiring'}]");
my @wiring_file_content = File::Slurp::read_file($options{'files'}{'wiring'}, { 'chomp' => 1 });
foreach my $line (@wiring_file_content) {
    # Splitting the content of the csv data
    my @line_content = split(/[;]/, $line);
    # TODO: Implement configurable defaults
    my %connection = (
        'source'          => ALX::EN81346::to_string($line_content[0]),
        'target'          => ALX::EN81346::to_string($line_content[1]),
        'color'           => $line_content[3] ? $line_content[3] : 'BU',
        'gauge'           => $line_content[4] ? $line_content[4] : '1mm',
        'length'          => $line_content[5] ? $line_content[5] : '0,666mm',
        'comment'         => $line_content[6],
    );

    $logger->debug("Inspection connection [$connection{'source'} <-> $connection{'target'}]");
    unless ($connection{'source'} && $connection{'target'}) {
        $logger->warn("Target and/or source connections are invalid, skipping processing connection");
        next;
    }

    # Skipping further processing, if the wiring is a cable connection
    if (ALX::EN81346::to_string($line_content[2])) {
        $logger->debug("Cable [" . ALX::EN81346::to_string($line_content[2]) .
            "] detected, skipping further wire processing");
        next;
    }

    # TODO: The handling of mm² and AWG gauge must be implemented
    if ($connection{'gauge'}) {
        $connection{'gauge'} =~ s/([0-9,.]+) ?([mawgMAWG]{2,3}).*/$1$2/gi;
        $logger->debug("Wire gauge [$connection{'gauge'}] detected for the connection");
    }

    push(@connections, \%connection);
    #print Dumper \%connection;
    print "$line\n";
}

#print Dumper \@connections;

# Create a new Excel workbook
my $excel_file = File::Spec->rel2abs($options{'files'}{'target'}{'file'});
$logger->info("Creating the excel output [$excel_file]");
{
    my $workbook = Excel::Writer::XLSX->new($excel_file) || $logger->logdie("Failed to open the output file");
    $workbook->set_properties(
        title    => 'clipx WIRE assist data file',
        author   => 'Alexander Thiel',
        comments => 'Created with Kabelsalat wire data crawler',
    );

    my $worksheet = $workbook->add_worksheet($options{'files'}{'target'}{'table'});

    # There is a weired behaviour in the wire guide software which causes crashes, if
    # cells have no individual format applied
    my $header_format = $workbook->add_format(num_format => 0x31);
    for (my $row = 0; $row < 8; $row++) {
        for (my $col = 0; $col < 34; $col++) {
            $worksheet->write_blank($row, $col, $header_format);
        }
    }
    my $special16_format = $workbook->add_format(font => 'Microsoft Sans Serif', size => 16, num_format => 0x31);
    my $special22_format = $workbook->add_format(font => 'Microsoft Sans Serif', size => 22, num_format => 0x31);
    $worksheet->write_blank('B6', $special22_format);
    $worksheet->write_blank('I2', $special16_format);
    $worksheet->write_blank('I3', $special16_format);

    # The text format for the data cells
    my $text_format = $workbook->add_format(num_format => 0x31);

    # Writing some dummy data to test the import into the wire assist software
    # HINT: Strings must be converted to windows codeset
    for (my $i = 0; $i < scalar(@connections); $i++) {
        my $row = 7 + $i;
        my %connection = %{$connections[$i]};

        $worksheet->write_string($row, 0, $i + 1, $text_format);
        # Source side information
        $worksheet->write_string($row, 1, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, '==')), $text_format); # Funktionale Zuordnung
        $worksheet->write_string($row, 2, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, '=')), $text_format);  # Anlage
        $worksheet->write_string($row, 3, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, '++')), $text_format); # Aufstellungsort
        $worksheet->write_string($row, 4, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, '+')), $text_format);  # Einbauort
        $worksheet->write_string($row, 5, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, '-')), $text_format);  # BMK
        $worksheet->write_string($row, 6, decode('utf-8', ALX::EN81346::to_string($connection{'source'}, ':')), $text_format);  # Anschluss
        $worksheet->write_blank($row, 7, $text_format);                                                                         # Seite
        $worksheet->write_string($row, 8, decode('utf-8', 'Aderendhülse_10mm_teilisoliert'), $text_format);                     # Verbindungsende-Behandlung
        $worksheet->write_blank($row, 9, $text_format);                                                                         # Doppelhülse bei Doppelbelegung
        $worksheet->write_string($row, 10, decode('utf-8', 'Nach oben, nach links'), $text_format);                             # Verlegerichtung
        # Target side information
        $worksheet->write_string($row, 11, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, '==')), $text_format); # Funktionale Zuordnung
        $worksheet->write_string($row, 12, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, '=')), $text_format);  # Anlage
        $worksheet->write_string($row, 13, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, '++')), $text_format); # Aufstellungsort
        $worksheet->write_string($row, 14, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, '+')), $text_format);  # Einbauort
        $worksheet->write_string($row, 15, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, '-')), $text_format);  # BMK
        $worksheet->write_string($row, 16, decode('utf-8', ALX::EN81346::to_string($connection{'target'}, ':')), $text_format);  # Anschluss
        $worksheet->write_blank($row, 17, $text_format);                                                                         # Seite
        $worksheet->write_string($row, 18, decode('utf-8', 'Aderendhülse_6mm_teilisoliert'), $text_format);                      # Verbindungsende-Behandlung
        $worksheet->write_blank($row, 19, $text_format);                                                                         # Doppelhülse bei Doppelbelegung
        $worksheet->write_string($row, 20, decode('utf-8', 'Nach oben, nach links'), $text_format);                              # Verlegerichtung
        # The wire data
        $worksheet->write_string($row, 21, decode('utf-8', 'BN'), $text_format);     # Farbe
        $worksheet->write_string($row, 22, decode('utf-8', '1,5'), $text_format);    # Querschnitt
        $worksheet->write_string($row, 23, decode('utf-8', 'H07V-K'), $text_format); # Typenbezeichung (Optional)
        $worksheet->write_blank($row, 24, $text_format);                             # Artikelnummer
        $worksheet->write_string($row, 25, decode('utf-8', '0,001m'), $text_format); # Länge
        $worksheet->write_blank($row, 26, $text_format);                             # Bündel
        $worksheet->write_blank($row, 27, $text_format);                             # Bündelgruppe
        $worksheet->write_blank($row, 28, $text_format);                             # Funktionsdefinition
        $worksheet->write_blank($row, 29, $text_format);                             # Paarindex
        $worksheet->write_blank($row, 30, $text_format);                             # Potential
        $worksheet->write_blank($row, 31, $text_format);                             # Verbindungsbezeichnung
        # Software internals for wire assist
        $worksheet->write_string($row, 32, decode('utf-8', 'Diese Werte wurden mit dem Kabelsalat-Crawler generiert'), $text_format); # Hinweis
        $worksheet->write_boolean($row, 33, 0, $text_format);                                                                         # Abgearbeitet
    }
    $workbook->close();
}

=pod

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2022 Alexander Thiel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

__DATA__

<log>
    level=INFO
</log>

<files>
    wiring = "./data/wiring.txt"
    devices = "./data/devices.txt"
    <target>
        file = "./data/wire_assist_generated.xlsx"
        table = "ECAD export"
    </target>
</files>
