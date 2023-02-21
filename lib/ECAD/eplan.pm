package ECAD::eplan;
use strict;
use warnings FATAL => 'all';

use Log::Log4perl;
use Log::Log4perl::Logger;

our $VERSION = '0.1';
$VERSION =~ tr/_//d;

use Exporter 'import';
our @EXPORT = qw(import devices import_wiring);  # symbols to export on request

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

sub import_wiring($;) {

}

1;
