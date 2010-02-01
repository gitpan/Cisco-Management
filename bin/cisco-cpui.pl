#!/usr/bin/perl

use strict;
use Cisco::Management;
use Getopt::Long qw(:config no_ignore_case); #bundling
use Pod::Usage;

my %opt;
my ($opt_help, $opt_man);

GetOptions(
  'community=s'  => \$opt{'community'},
  'help!'        => \$opt_help,
  'man!'         => \$opt_man
) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1) if defined $opt_help;
pod2usage(-verbose => 2) if defined $opt_man;

# Make sure at least one arg was provided
if (!@ARGV) {
    pod2usage(-verbose => 0, -message => "$0: host required\n")
}

$opt{'community'} = $opt{'community'} || 'private';

for (@ARGV) {
    print "\n-- $_ --\n";

    my $cm;
    if (!defined($cm = Cisco::Management->new(
                              hostname  => $_,
                              community => $opt{'community'}
                             ))) {
        printf "Error: %s\n", Cisco::Management->error;
        next
    }

    if (defined(my $cpu = $cm->cpu_info())) {        
        print "CPU Name            | 5 second(%) | 1 minute(%) | 5 minute(%)\n";
        print "--------------------|-------------|-------------|------------\n";
        for (0..$#{$cpu}) {
            printf "%-20s|%9.2f    |%9.2f    |%9.2f\n", 
                $cpu->[$_]->{'Name'}, 
                $cpu->[$_]->{'5sec'},
                $cpu->[$_]->{'1min'},
                $cpu->[$_]->{'5min'}
        }
    } else {
        printf "Error: %s\n", Cisco::Management->error
    }
    $cm->close()
}

__END__

########################################################
# Start POD
########################################################

=head1 NAME

CISCO-CPUI - Cisco CPU Information

=head1 SYNOPSIS

 cisco-cpui [options] host [...]

=head1 DESCRIPTION

Print CPU information for provided Cisco device.

=head1 ARGUMENTS

 host             The Cisco device to manage.

=head1 OPTIONS

 -c <snmp_rw>     SNMP read/write community.
 --community      DEFAULT:  (or not specified) 'private'.

=head1 LICENSE

This software is released under the same terms as Perl itself.
If you don't know what that means visit L<http://perl.com/>.

=head1 AUTHOR

Copyright (C) Michael Vincent 2010

L<http://www.VinsWorld.com>

All rights reserved

=cut
