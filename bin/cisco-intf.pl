#!/usr/bin/perl

use strict;
use Cisco::Management;
use Getopt::Long qw(:config no_ignore_case); #bundling
use Pod::Usage;

my %opt;
my ($opt_help, $opt_man);

GetOptions(
  'community=s'  => \$opt{'community'},
  'down!'        => \$opt{'down'},
  'interfaces=s' => \$opt{'interfaces'},
  'up!'          => \$opt{'up'},
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

my $oper;
if (defined($opt{'up'})) {
    $oper = 'UP'
} elsif (defined($opt{'down'})) {
    $oper = 'DOWN'
}

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

    my %params;
    if (defined($opt{'interfaces'})) { 

        if ($opt{'interfaces'} =~ /^[A-Za-z]/) {
            my @temp;
            my @ifs = split /\s+/, $opt{'interfaces'};
            for (@ifs) {
                if (defined(my $if = $cm->interface_getbyname(interface => $_, index => 1))) {
                    push @temp, $if
                } else {
                    printf "Error: %s\n", Cisco::Management->error
                }
            }
            $params{'interfaces'} = join ',', @temp
        } else {
            $params{'interfaces'} = $opt{'interfaces'}
        }

        $params{'operation'}  = $oper;
        if (defined(my $ifs = $cm->interface_updown(%params))) {        
            print "$_: Admin $oper interfaces = @{$ifs}\n"
        } else {
            printf "Error: %s\n", Cisco::Management->error
        }
    } else {
        if (defined(my $ifs = $cm->interface_info())) {        
            print "Index Description               Speed/Duplex Admin/Oper IP(s)\n";
            print "--------------------------------------------------------------\n";
            for (sort {$a <=> $b} (keys(%{$ifs}))) {
                printf "%5i %-25s %-4i/%-7s %4s/%-4s ", 
                    $_, 
                    $ifs->{$_}->{Description},
                    $ifs->{$_}->{Speed}/1000000,
                    $ifs->{$_}->{Duplex},
                    $ifs->{$_}->{AdminStatus},
                    $ifs->{$_}->{OperStatus};
                    if (defined(my $ips = $ifs->{$_}->interface_info_ip())) {
                        for (0..$#{$ips}) {
                            print " $ips->[$_]->{'IPAddress'}"
                        }
                    }
                print "\n"
            }
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

CISCO-INTF - Cisco Interface Manager

=head1 SYNOPSIS

 cisco-intf [options] host [...]

=head1 DESCRIPTION

Admin up/down interfaces on Cisco devices.

=head1 ARGUMENTS

 host             The Cisco device to manage.

=head1 OPTIONS

 -c <snmp_rw>     SNMP read/write community.
 --community      DEFAULT:  (or not specified) 'private'.

 -d               Admin down interface.
 --down           DEFAULT:  (or not specified) [UP].

 -i IF            Interfaces to operate on.
 --interfaces     
                  IF can be number meaning ifIndex.  Range can be 
                  provided.  Range uses , and - for individual and 
                  all inclusive.  Example:
                    2-4,11
                  
                  IF can be interface name(s).  If multiple, use 
                  quotes to surround the list and spaces to separate.
                  Example:
                    "gig0/0/1 serial1/0 f0/1"

                  DEFAULT:  (or not specified) [all].

 -u               Admin up interface.
 --up             DEFAULT:  (or not specified) [UP].

=head1 LICENSE

This software is released under the same terms as Perl itself.
If you don't know what that means visit L<http://perl.com/>.

=head1 AUTHOR

Copyright (C) Michael Vincent 2010

L<http://www.VinsWorld.com>

All rights reserved

=cut
