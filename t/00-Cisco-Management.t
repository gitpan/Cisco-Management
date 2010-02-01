#!/usr/bin/perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Cisco-Management.t'

use strict;
use Test::Simple tests => 10;

use Cisco::Management;
ok(1, "Loading Module"); # If we made it this far, we're ok.

#########################

my $cm;

# Session with no hostname
    # Session
    if (defined($cm = Cisco::Management->new())) {
        ok(1, "Session New")
    } else {
        ok(0, "Session New")
    }

    # Check
    ok (($cm->{'_SESSION_'}->{'_hostname'} eq 'localhost') && (!exists($cm->{'hostname'})), "Hostname - assume localhost");

    # Close
    $cm->close();
    ok(1, "Session Close");

# Session with hostname
    # Session
    if (defined($cm = Cisco::Management->new('10.10.10.10'))) {
        ok(1, "Session New")
    } else {
        ok(0, "Session New")
    }

    # Check
    ok (($cm->{'_SESSION_'}->{'_hostname'} eq '10.10.10.10') && ($cm->{'hostname'} eq '10.10.10.10'), "Hostname - provided");

    # Close
    $cm->close();
    ok(1, "Session Close");

# Session with hostname and community
    # Session
    if (defined($cm = Cisco::Management->new(
        hostname  => '1.1.1.1',
        community => 'testcomm'))) {
        ok(1, "Session New")
    } else {
        ok(0, "Session New")
    }

    # Check
    ok (($cm->{'_SESSION_'}->{'_hostname'} eq '1.1.1.1') 
    && ($cm->{'hostname'} eq '1.1.1.1') 
    && ($cm->{'_SESSION_'}->{'_security'}->{'_community'} eq 'testcomm') 
    && ($cm->{'community'} eq 'testcomm'), 
    "Hostname and community - provided");

    # Close
    $cm->close();
    ok(1, "Session Close");
