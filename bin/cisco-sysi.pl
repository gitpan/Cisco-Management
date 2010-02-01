#!/usr/bin/perl

use strict;
use Cisco::Management;
use Getopt::Long qw(:config no_ignore_case); #bundling
use Pod::Usage;

my %opt;
my ($opt_help, $opt_man);

GetOptions(
  'community=s'   => \$opt{'community'},
  'help!'         => \$opt_help,
  'man!'          => \$opt_man
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

    if (defined(my $sysinfo = $cm->system_info())) {        
        printf "Description = %s\n", $sysinfo->system_info_description;
        printf "ObjectID    = %s\n", $sysinfo->system_info_objectID;
        printf "Uptime      = %s\n", $sysinfo->system_info_uptime;
        printf "Conctact    = %s\n", $sysinfo->system_info_contact;
        printf "Name        = %s\n", $sysinfo->system_info_name;
        printf "Location    = %s\n", $sysinfo->system_info_location;
        print  "Services    = ";
            print "$_ " for (@{$sysinfo->system_info_services});
        printf "\n\nOS Version  = %s\n", $sysinfo->system_info_osversion;

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

CISCO-SYSI - Cisco System Information

=head1 SYNOPSIS

 cisco-sysi [options] host [...]

=head1 DESCRIPTION

Print system information for provided Cisco device.

=head1 ARGUMENTS

 host             The Cisco device to connect to.

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
