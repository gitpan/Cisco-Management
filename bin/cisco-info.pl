#!/usr/bin/perl

use strict;
use Cisco::Management;
use Getopt::Long qw(:config no_ignore_case); #bundling
use Pod::Usage;

my %opt;
my ($opt_help, $opt_man);

GetOptions(
  'community=s'  => \$opt{community},
  'CPU!'         => \$opt{cpu},
  'Kilobytes!'   => \$opt{k},
  'memory!'      => \$opt{mem},
  'Megabytes!'   => \$opt{m},
  'system!'      => \$opt{sys},
  'help!'        => \$opt_help,
  'man!'         => \$opt_man
) or pod2usage(-verbose => 0);

pod2usage(-verbose => 1) if defined $opt_help;
pod2usage(-verbose => 2) if defined $opt_man;

# Make sure at least one arg was provided
if (!@ARGV) {
    pod2usage(-verbose => 0, -message => "$0: host required\n")
}

$opt{community} = $opt{community} || 'private';
if (!defined($opt{cpu}) && 
    !(defined($opt{mem}) || defined($opt{k}) || defined($opt{m})) && 
    !defined($opt{sys})) {
    $opt{sys} = 1
}

for (@ARGV) {
    print "\n-- $_ --\n";

    my $cm;
    if (!defined($cm = Cisco::Management->new(
                              hostname  => $_,
                              community => $opt{community}
                             ))) {
        printf "Error: %s\n", Cisco::Management->error;
        next
    }

    if (defined($opt{cpu})) {
        if (defined(my $cpu = $cm->cpu_info())) {        
            print "CPU Name            | 5 second(%) | 1 minute(%) | 5 minute(%)\n";
            print "--------------------|-------------|-------------|------------\n";
            for (0..$#{$cpu}) {
                printf "%-20s|%9.2f    |%9.2f    |%9.2f\n", 
                    $cpu->[$_]->{Name}, 
                    $cpu->[$_]->{'5sec'},
                    $cpu->[$_]->{'1min'},
                    $cpu->[$_]->{'5min'}
            }
            print "\n"
        } else {
            printf "Error: %s\n", Cisco::Management->error
        }
    }

    if (defined($opt{mem}) || defined($opt{m}) || defined($opt{k})) {
        if (defined(my $mem = $cm->memory_info())) {
            my $params = 'B';
            if (defined($opt{k})) { $params = 'K' }
            if (defined($opt{m})) { $params = 'M' }

            printf "Memory Pool Name    |   Total(%s)    |    Used(%s)    |Percent(%%)\n", $params, $params;
            print  "--------------------|---------------|---------------|----------\n";
            for (0..$#{$mem}) {
                my ($Used, $Total);
                if       ($params eq 'K') { $Used  = $mem->[$_]->{Used}/1000;
                                            $Total = $mem->[$_]->{Total}/1000
                } elsif  ($params eq 'M') { $Used  = $mem->[$_]->{Used}/1000000;
                                            $Total = $mem->[$_]->{Total}/1000000
                } else                    { $Used  = $mem->[$_]->{Used};
                                            $Total = $mem->[$_]->{Total}
                }
                printf "%-20s|%15.2f|%15.2f|%7.2f\n", 
                    $mem->[$_]->{Name}, 
                    $Total,
                    $Used, 
                    $mem->[$_]->{Used}/$mem->[$_]->{Total}*100
            }
            print "\n"
        } else {
            printf "Error: %s\n", Cisco::Management->error
        }
    }

    if (defined($opt{sys})) {
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
            print "\n"
        } else {
            printf "Error: %s\n", Cisco::Management->error
        }
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

 -C               Provide CPU utilization.
 --CPU            DEFAULT:  (or not specified) [System info]

 -m               Provide memory utilization.
 --memory         DEFAULT:  (or not specified) [System info]

   -K             Provide memory utilization in Kilobytes
   --Kilobytes    DEFAULT:  (or not specified) [Bytes]

   -M             Provide memory utilization in Megabytes
   --Megabytes    DEFAULT:  (or not specified) [Bytes]

 -s               Provide system MIB information.
 --system         DEFAULT:  (or not specified) [System info]

=head1 LICENSE

This software is released under the same terms as Perl itself.
If you don't know what that means visit L<http://perl.com/>.

=head1 AUTHOR

Copyright (C) Michael Vincent 2010

L<http://www.VinsWorld.com>

All rights reserved

=cut
