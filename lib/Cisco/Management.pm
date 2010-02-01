package Cisco::Management;

########################################################
#
# AUTHOR = Michael Vincent
# www.VinsWorld.com
#
########################################################

require 5.005;

use strict;
use Exporter;

use Sys::Hostname;
use IO::Socket;
use Net::SNMP qw(:asn1 :snmp DEBUG_ALL);

our $VERSION     = '0.01';
our @ISA         = qw(Exporter);
our @EXPORT      = qw();
our %EXPORT_TAGS = (
                    'all'      => [qw()],
                    'password' => [qw(password_decrypt password_encrypt)]
                   );
our @EXPORT_OK   = (@{$EXPORT_TAGS{'password'}});

########################################################
# Start Variables
########################################################
# Cisco's XOR key
my @xlat = ( 0x64, 0x73, 0x66, 0x64, 0x3B, 0x6B, 0x66, 0x6F, 0x41, 0x2C, 
             0x2E, 0x69, 0x79, 0x65, 0x77, 0x72, 0x6B, 0x6C, 0x64, 0x4A, 
             0x4B, 0x44, 0x48, 0x53, 0x55, 0x42, 0x73, 0x67, 0x76, 0x63, 
             0x61, 0x36, 0x39, 0x38, 0x33, 0x34, 0x6E, 0x63, 0x78, 0x76, 
             0x39, 0x38, 0x37, 0x33, 0x32, 0x35, 0x34, 0x6B, 0x3B, 0x66, 
             0x67, 0x38, 0x37
           );

our $LASTERROR;
########################################################
# End Variables
########################################################

########################################################
# Start Public Module
########################################################

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my %params = (
        community => 'private',
        port      => 161,
        timeout   => 10
    );

    my %args;
    if (@_ == 1) {
        ($params{'hostname'}) = @_
    } else {
        %args = @_;
        for (keys(%args)) {
            if (/^-?port$/i) {
                $params{'port'} = $args{$_}
            } elsif (/^-?community$/i) {
                $params{'community'} = $args{$_}
            } elsif ((/^-?hostname$/i) || (/^-?(?:de?st|peer)?addr$/i)) {
                $params{'hostname'} = $args{$_}
            } elsif (/^-?timeout$/i) {
                $params{'timeout'} = $args{$_}
            }
        }
    }

    my ($session, $error) = Net::SNMP->session(%params);

    if (!defined($session)) {
        $LASTERROR = "Error creating Net::SNMP object: $error";
        return(undef)
    }

    return bless {
                  %params,       # merge user parameters
                  '_SESSION_' => $session
                 }, $class
}

sub session {
    my $self = shift;
    return $self->{'_SESSION_'}
}

sub config_copy {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $cc;
    foreach my $key (keys(%{$self})) {
        # everything but '_xxx_'
        $key =~ /^\_.+\_$/ and next;
        $cc->{$key} = $self->{$key}
    }

    my %params = (
        op         => 'wr',
        catos      => 0,
        source     => 4,
        dest       => 3,
        tftpserver => inet_ntoa((gethostbyname(hostname))[4])
    );

    my %args;
    if (@_ == 1) {
        $LASTERROR = "Insufficient number of args - @_";
        return(undef)
    } else {
        %args = @_;
        for (keys(%args)) {
            if ((/^-?(?:tftp)?server$/i) || (/^-?tftp$/)) {
                $params{'tftpserver'} = $args{$_}
            } elsif (/^-?catos$/i) {
                if ($args{$_} == 1) {
                    $params{'catos'} = 1
                }
            } elsif (/^-?source$/i) {
                if ($args{$_} =~ /^run(?:ning)?(?:-config)?$/i) {
                    $params{'source'} = 4
                } elsif ($args{$_} =~ /^start(?:up)?(?:-config)?$/i) {
                    $params{'source'} = 3
                } else {
                    $params{'source'} = 1;
                    $params{'op'}     = 'put';
                    $params{'file'}   = $args{$_}
                }
            } elsif (/^-?dest(?:ination)?$/i) {
                if ($args{$_} =~ /^run(?:ning)?(?:-config)?$/i) {
                    $params{'dest'} = 4
                } elsif ($args{$_} =~ /^start(?:up)?(?:-config)?$/i) {
                    $params{'dest'} = 3
                } else {
                    $params{'dest'} = 1;
                    $params{'op'}   = 'get';
                    $params{'file'} = $args{$_}
                }
            }
        }
    }
    $cc->{'_CONFIGCOPY_'}{'_params_'} = \%params;

    if ($params{'source'} == $params{'dest'}) {
        $LASTERROR = "Source and destination cannot be same";
        return(undef)
    }

    my $response;
    my $instance = int(rand(1024)+1024);
    my %err = (
        1 => "Unknown",
        2 => "Bad file name",
        3 => "Timeout",
        4 => "No memory",
        5 => "No config",
        6 => "Unsupported protocol",
        7 => "Config apply fail",
        8 => "System not ready",
        9 => "Request abort"
    );

    # wr mem
    if ($params{'op'} eq 'wr') {
        if ($params{'catos'}) {
            $LASTERROR = "Copy run start not allowed on CatOS";
            return(undef)
        }
        # ccCopyEntryRowStatus (5 = createAndWait, 6 = destroy)
        $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 6);

        if (!defined($response)) {
            $LASTERROR = "[wr mem] NOT SUPPORTED - Trying old way";
            $response = $session->set_request('1.3.6.1.4.1.9.2.1.54.0', INTEGER, 1);
            if (defined($response)) {
                return bless $cc, $class
            } else {
                $LASTERROR = "[wr mem] FAILED (new/old)";
                return(undef)
            }
        }

          # ccCopySourceFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
        $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.3.' . $instance, INTEGER, $params{'source'});
          # ccCopyDestFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
        $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.4.' . $instance, INTEGER, $params{'dest'})

    # TFTP PUT (to device)
    } elsif ($params{'op'} eq 'put') {
        # CatOS
        if ($params{'catos'}) {
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.1.0', OCTET_STRING, $params{'tftpserver'});
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.2.0', OCTET_STRING, $params{'file'});
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.3.0', INTEGER, 1);
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.4.0', INTEGER, 2);
            if (defined($response)) {
                return bless $cc, $class
            } else {
                $LASTERROR = "[CatOS TFTP put] FAILED";
                return(undef)
            }

        # IOS
        } else {
            # ccCopyEntryRowStatus (5 = createAndWait, 6 = destroy)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 6);
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 5);

              # ccCopyProtocol (1 = TFTP)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.2.' . $instance, INTEGER, 1);

            if (!defined($response)) {
                $LASTERROR = "[IOS TFTP put] NOT SUPPORTED - Trying old way";
                $response = $session->set_request('1.3.6.1.4.1.9.2.1.50.' . $params{'tftpserver'}, OCTET_STRING, $params{'file'});
                if (defined($response)) {
                    return bless $cc, $class
                } else {
                    $LASTERROR = "[IOS TFTP put] FAILED (new/old)";
                    return(undef)
                }
            }
              # ccCopySourceFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.3.' . $instance, INTEGER, 1);
              # ccCopyDestFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.4.' . $instance, INTEGER, $params{'dest'});
              # New way
              # ccCopyServerAddressType (1 = IPv4, 2 = IPv6)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.15.' . $instance, INTEGER, 1);

            if (defined($response)) {
                  # ccCopyServerAddressRev1
                $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.16.' . $instance, OCTET_STRING, $params{'tftpserver'})
            } else {
                  # Deprecated
                  # ccCopyServerAddress
                $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.5.' . $instance, IPADDRESS, $params{'tftpserver'})
            }
              # ccCopyFileName
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.6.' . $instance, OCTET_STRING, $params{'file'})
        }

    # TFTP GET (from device)
    } elsif ($params{'op'} eq 'get') {
        # CatOS
        if ($params{'catos'}) {
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.1.0', OCTET_STRING, $params{'tftpserver'});
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.2.0', OCTET_STRING, $params{'file'});
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.3.0', INTEGER, 1);
            $response = $session->set_request('1.3.6.1.4.1.9.5.1.5.4.0', INTEGER, 3);
            if (defined($response)) {
                return bless $cc, $class
            } else {
                $LASTERROR = "[CatOS TFTP get] FAILED";
                return(undef)
            }

        # IOS
        } else {
            # ccCopyEntryRowStatus (5 = createAndWait, 6 = destroy)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 6);
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 5);

              # ccCopyProtocol (1 = TFTP)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.2.' . $instance, INTEGER, 1);

            if (!defined($response)) {
                $LASTERROR = "[IOS TFTP get] NOT SUPPORTED - Trying old way";
                $response = $session->set_request('1.3.6.1.4.1.9.2.1.55.' . $params{'tftpserver'}, OCTET_STRING, $params{'file'});
                if (defined($response)) {
                    return bless $cc, $class
                } else {
                    $LASTERROR = "[IOS TFTP get] FAILED (new/old)";
                    return(undef)
                }
            }
              # ccCopySourceFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.3.' . $instance, INTEGER, $params{'source'});
              # ccCopyDestFileType (1 = networkFile, 3 = startupConfig, 4 = runningConfig)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.4.' . $instance, INTEGER, 1);
              # New way
              # ccCopyServerAddressType (1 = IPv4, 2 = IPv6)
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.15.' . $instance, INTEGER, 1);

            if (defined($response)) {
                  # ccCopyServerAddressRev1
                $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.16.' . $instance, OCTET_STRING, $params{'tftpserver'})
            } else {
                  # Deprecated
                  # ccCopyServerAddress
                $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.5.' . $instance, IPADDRESS, $params{'tftpserver'})
            }
              # ccCopyFileName
            $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.6.' . $instance, OCTET_STRING, $params{'file'})
        }
    }
    # ccCopyEntryRowStatus (4 = createAndGo, 6 = destroy)
    $response = $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 1);

    # Check status, wait done
    $response = $session->get_request('1.3.6.1.4.1.9.9.96.1.1.1.1.10.' . $instance);
    if (!defined($response)) {
        $LASTERROR = "NOT SUPPORTED (after setup)";
        return(undef)
    }
    while ($response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.10.' . $instance} <= 2) {
        $response = $session->get_request('1.3.6.1.4.1.9.9.96.1.1.1.1.10.' . $instance)
    }
    # Success
    if ($response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.10.' . $instance} == 3) {
        $response = $session->get_request('1.3.6.1.4.1.9.9.96.1.1.1.1.11.' . $instance);
        $cc->{'_CONFIGCOPY_'}{'StartTime'} = $response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.11.' . $instance};
        $response = $session->get_request('1.3.6.1.4.1.9.9.96.1.1.1.1.12.' . $instance);
        $cc->{'_CONFIGCOPY_'}{'EndTime'}   = $response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.12.' . $instance};
        $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 6);
        return bless $cc, $class
    # Error
    } elsif ($response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.10.' . $instance} == 4) {
        $response = $session->get_request('1.3.6.1.4.1.9.9.96.1.1.1.1.13.' . $instance);
        $session->set_request('1.3.6.1.4.1.9.9.96.1.1.1.1.14.' . $instance, INTEGER, 6);
        $LASTERROR = $err{$response->{'1.3.6.1.4.1.9.9.96.1.1.1.1.13.' . $instance}};
        return(undef)
    } else { 
        $LASTERROR = "Cannot determine success or failure";
        return(undef)
    }
}

sub config_copy_starttime {
    my $self = shift;
    return $self->{'_CONFIGCOPY_'}{'StartTime'}
}

sub config_copy_endtime {
    my $self = shift;
    return $self->{'_CONFIGCOPY_'}{'EndTime'}
}

sub cpu_info {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my ($type, $cpu5min);
    # IOS releases < 12.0(3)T
    if (($cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.2.1.58")) && (defined($cpu5min->[0]))) {
        $type = 1
    # 12.0(3)T < IOS releases < 12.2(3.5)
    } elsif (($cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.5")) && (defined($cpu5min->[0]))) {
        $type = 2
    # IOS releases > 12.2(3.5)
    } elsif (($cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.8")) && (defined($cpu5min->[0]))) {
        $type = 3
    } else {
        $LASTERROR = "Cannot determine CPU type";
        return(undef)
    }

    my %cpuType = (
        1 => 'IOS releases < 12.0(3)T',
        2 => '12.0(3)T < IOS releases < 12.2(3.5)',
        3 => 'IOS releases > 12.2(3.5)'
    );

    my @cpuName;
    # Get multiple CPU names
    if ($type > 1) {
        my $temp = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.2");
        for (0..$#{$temp}) {
            if (defined(my $result = $session->get_request( -varbindlist => ['1.3.6.1.2.1.47.1.1.1.1.7.' . $temp->[$_]] ))) {
                $cpuName[$_] = $result->{'1.3.6.1.2.1.47.1.1.1.1.7.' . $temp->[$_]}
            } else {
                $LASTERROR = "Cannot get CPU name for type $type";
                return(undef)
            }
        }
    }

    my ($cpu5sec, $cpu1min);
    if ($type == 1) {
        $cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.2.1.58");
        $cpu5sec = &_snmpgetnext($session,"1.3.6.1.4.1.9.2.1.56");
        $cpu1min = &_snmpgetnext($session,"1.3.6.1.4.1.9.2.1.57")
    } elsif ($type == 2) {
        $cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.5");
        $cpu5sec = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.3");
        $cpu1min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.4")
    } elsif ($type == 3) {
        $cpu5min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.8");
        $cpu5sec = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.6");
        $cpu1min = &_snmpgetnext($session,"1.3.6.1.4.1.9.9.109.1.1.1.1.7")
    } else { } 

    my @CPUInfo;
    for my $cpu (0..$#{$cpu5min}) {
        my %CPUInfoHash;
        $CPUInfoHash{'Name'}    = $cpuName[$cpu];
        $CPUInfoHash{'5sec'}    = $cpu5sec->[$cpu];
        $CPUInfoHash{'1min'}    = $cpu1min->[$cpu];
        $CPUInfoHash{'5min'}    = $cpu5min->[$cpu];
        $CPUInfoHash{'_type_'}  = $cpuType{$type};
        push @CPUInfo, \%CPUInfoHash
    }
    return \@CPUInfo
}

sub interface_getbyindex {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $uIfx;
    my %args;
    if (@_ == 1) {
        ($uIfx) = @_;
        if ($uIfx !~ /^\d+$/) {
            $LASTERROR = "Not a valid index - $uIfx";
            return(undef)
        }
    } else {
        %args = @_;
        for (keys(%args)) {
            if ((/^-?interface$/i) || (/^-?index$/i)) {
                if ($args{$_} =~ /^\d+$/) {
                    $uIfx = $args{$_}
                } else {
                    $LASTERROR = "Not a valid index - $args{$_}";
                    return(undef)
                }
            }
        }
    }
    if (!defined($uIfx)) {
        $LASTERROR = "No index provided";
        return(undef)
    }
    my $rIf  = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.2');
    if (!defined($rIf)) {
        $LASTERROR = "Cannot get interface names from device";
        return(undef)
    }
    my $rIfx = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.1');

    for (0..$#{$rIfx}) {
        if ($rIfx->[$_] == $uIfx) {
            return $rIf->[$_]
        }
    }
    $LASTERROR = "Cannot find interface for index - $uIfx";
    return(undef)
}

sub interface_getbyname {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my %params = (
        'index' => 0
    );

    my %args;
    if (@_ == 1) {
        ($params{'uIf'}) = @_;
    } else {
        %args = @_;
        for (keys(%args)) {
            if (/^-?interface$/i) {
                $params{'uIf'} = $args{$_}
            } elsif (/^-?index$/i) {
                if ($args{$_} == 1) {
                    $params{'index'} = 1
                }
            }
        }
    }
    if (!exists($params{'uIf'})) {
        $LASTERROR = "No interface provided";
        return(undef)
    }

    my $rIf  = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.2');
    if (!defined($rIf)) {
        $LASTERROR = "Cannot get interface names from device";
        return(undef)
    }
    my $rIfx = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.1');

    # user Provided
    my @parts = split /([0-9])/, $params{'uIf'}, 2;
    my $uIfNamePart =  shift @parts;
    my $uIfNumPart  =  "@parts";
       $uIfNumPart  =~ s/\s+//;

    my @matches;
    my $idx;
    for (0..$#{$rIf}) {
        # Real Names
        @parts = split /([0-9])/, $rIf->[$_], 2;
        my $rIfNamePart =  shift @parts;
        my $rIfNumPart  =  "@parts";
           $rIfNumPart  =~ s/\s+//;
        if (($rIfNamePart =~ /^$uIfNamePart/i) && ($rIfNumPart eq $uIfNumPart)) {
            push @matches, $rIf->[$_];
            $idx = $rIfx->[$_]
        }
    }
    if (@matches == 1) {
        if ($params{'index'} == 0) {
            return "@matches"
        } else {
            return $idx
        }
    } elsif (@matches == 0) {
        $LASTERROR = "Cannot find interface - $params{'uIf'}";
        return(undef)
    } else {
        print "Interface $params{'uIf'} not specific - [@matches]";
        return(undef)
    }
}

sub interface_info {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    # If Info
    my $Index       = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.1');
    if (!defined($Index)) {
        $LASTERROR = "Cannot get interface info";
        return(undef)
    }
    my $Description = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.2');
    my $Type        = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.3');
    my $MTU         = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.4');
    my $Speed       = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.5');

    my $Duplex      = &_snmpgetnext($session, '1.3.6.1.2.1.10.7.2.1.19');

    my $PhysAddress = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.6');
    my $AdminStatus = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.7');
    my $OperStatus  = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.8');
    my $LastChange  = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.9');

    # IP Info
    my $IPIndex     = &_snmpgetnext($session, '1.3.6.1.2.1.4.20.1.2');
    if (!defined($Index)) {
        $LASTERROR = "Cannot get interface info (IP)";
        return(undef)
    }
    my $IPAddress  = &_snmpgetnext($session, '1.3.6.1.2.1.4.20.1.1');
    my $IPMask     = &_snmpgetnext($session, '1.3.6.1.2.1.4.20.1.3');

    my %IPInfo;
    for (0..$#{$IPIndex}) {
        my %IPInfoHash;
        $IPInfoHash{'IPAddress'} = $IPAddress->[$_];
        $IPInfoHash{'IPMask'}    = $IPMask->[$_];
        push @{$IPInfo{$IPIndex->[$_]}}, \%IPInfoHash
    }

    my %UpDownStatus = (
        1 => 'UP',
        2 => 'DOWN',
        3 => 'TEST',
        4 => 'UNKNOWN',
        5 => 'DORMANT',
        6 => 'NOTPRESENT',
        7 => 'LOWLAYERDOWN'
    );
    my %DuplexType = (
        1 => 'UNKNOWN',
        2 => 'HALF',
        3 => 'FULL'
    );
    my %IfInfo;
    for my $ifs (0..$#{$Index}) {
        my %IfInfoHash;
        $IfInfoHash{'Index'}       = $Index->[$ifs];
        $IfInfoHash{'Description'} = $Description->[$ifs];
        $IfInfoHash{'Type'}        = $Type->[$ifs];
        $IfInfoHash{'MTU'}         = $MTU->[$ifs];
        $IfInfoHash{'Speed'}       = $Speed->[$ifs];

        $IfInfoHash{'Duplex'}      = exists($DuplexType{$Duplex->[$ifs]}) ? $DuplexType{$Duplex->[$ifs]} : $Duplex->[$ifs];

        $IfInfoHash{'PhysAddress'} = ($PhysAddress->[$ifs] =~ /^\0/) ? unpack('H12', $PhysAddress->[$ifs]) : (($PhysAddress->[$ifs] =~ /^0x/) ? substr($PhysAddress->[$ifs],2) : $PhysAddress->[$ifs]);
        $IfInfoHash{'AdminStatus'} = exists($UpDownStatus{$AdminStatus->[$ifs]}) ? $UpDownStatus{$AdminStatus->[$ifs]} : $AdminStatus->[$ifs];
        $IfInfoHash{'OperStatus'}  = exists($UpDownStatus{$OperStatus->[$ifs]}) ? $UpDownStatus{$OperStatus->[$ifs]} : $OperStatus->[$ifs];
        $IfInfoHash{'LastChange'}  = $LastChange->[$ifs];
        if (exists($IPInfo{$Index->[$ifs]})) {
            $IfInfoHash{'_IPINFO_'} = $IPInfo{$Index->[$ifs]}
        }
        $IfInfo{$Index->[$ifs]} = bless \%IfInfoHash
    }
    return bless \%IfInfo, $class
}

sub interface_info_ip {
    my $self  = shift;
    return $self->{'_IPINFO_'}
}

sub interface_updown {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my %op     = (
        'UP'   => 1,
        'DOWN' => 2
    );
    my %params = (
        'oper' => $op{'UP'}
    );

    my %args;
    my $oper = 'UP';
    if (@_ == 1) {
        ($params{'ifs'}) = @_;
        if (!defined($params{'ifs'} = _get_range($params{'ifs'}))) {
            return(undef)
        }
    } else {
        %args = @_;
        for (keys(%args)) {
            if (/^-?interface(?:s)?$/i) {
                if (!defined($params{'ifs'} = _get_range($args{$_}))) {
                    return(undef)
                }
            } elsif ((/^-?operation$/i) || (/^-?command$/i)) {
                if (exists($op{uc($args{$_})})) {
                    $params{'oper'} = $op{uc($args{$_})};
                    $oper = uc($args{$_})
                } else {
                    $LASTERROR = "Undefined operation";
                    return(undef)
                }
            }
        }
    }

    if (!defined($params{'ifs'})) {
        $params{'ifs'} = &_snmpgetnext($session, '1.3.6.1.2.1.2.2.1.1');
        if (!defined($params{'ifs'})) {
            $LASTERROR = "Cannot get interfaces to $oper";
            return(undef)
        }
    }

    my @intf;
    for (@{$params{'ifs'}}) {
        if (defined($session->set_request('1.3.6.1.2.1.2.2.1.7.' . $_, INTEGER, $params{'oper'}))) {
            push @intf, $_
        } else {
            $LASTERROR = "Failed to $oper interface $_";
            return(undef)
        }
    }
    return \@intf
}

sub line_clear {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my %params;
    my %args;
    if (@_ == 1) {
        ($params{'lines'}) = @_;
        if (!defined($params{'lines'} = _get_range($params{'lines'}))) {
            return(undef)
        }
    } else {
        %args = @_;
        for (keys(%args)) {
            if ((/^-?range$/i) || (/^-?line(?:s)?$/i)) {
                if (!defined($params{'lines'} = _get_range($args{$_}))) {
                    return(undef)
                }
            }
        }
    }

    if (!defined($params{'lines'})) {
        $params{'lines'} = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.20');
        if (!defined($params{'lines'})) {
            $LASTERROR = "Cannot get lines to clear";
            return(undef)
        }
    }

    my @lines;
    for (@{$params{'lines'}}) {
        if (defined($session->set_request('1.3.6.1.4.1.9.2.9.10.0', INTEGER, $_))) {
            push @lines, $_
        } else {
            $LASTERROR = "Failed to clear line $_";
            return(undef)
        }
    }
    return \@lines
}

sub line_info {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $Number     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.20');
    if (!defined($Number)) {
        $LASTERROR = "Cannot get line info";
        return(undef)
    }
    my $TimeActive = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.21');
    my $Noise      = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.19');
    my $User       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.18');
    my $Nses       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.17');
    my $Uses       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.16');
    my $Rotary     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.15');
    my $Sestmo     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.14');
    my $Tmo        = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.13');
    my $Esc        = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.12');
    my $Scrwid     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.11');
    my $Scrlen     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.10');
    my $Term       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.9');
    my $Loc        = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.8');
    my $Modem      = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.7');
    my $Flow       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.6');
    my $Speedout   = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.5');
    my $Speedin    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.4');
    my $Autobaud   = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.3');
    my $Type       = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.2');
    my $Active     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.2.1.1');

    my %LineTypes = (
        2 => 'CON',
        3 => 'TRM',
        4 => 'LNP',
        5 => 'VTY',
        6 => 'AUX'
    );
    my %LineModem = (
        2 => 'none',
        3 => 'callin',
        4 => 'callout',
        5 => 'cts-reqd',
        6 => 'ri-is-cd',
        7 => 'inout'
    );
    my %LineFlow = (
        2 => 'none',
        3 => 'sw-in',
        4 => 'sw-out',
        5 => 'sw-both',
        6 => 'hw-in',
        7 => 'hw-out',
        8 => 'hw-both'
    );
    my %LineInfo;
    for my $lines (0..$#{$Number}) {
        my %LineInfoHash;
        $LineInfoHash{'Number'}     = $Number->[$lines];
        $LineInfoHash{'TimeActive'} = $TimeActive->[$lines];
        $LineInfoHash{'Noise'}      = $Noise->[$lines];
        $LineInfoHash{'User'}       = $User->[$lines];
        $LineInfoHash{'Nses'}       = $Nses->[$lines];
        $LineInfoHash{'Uses'}       = $Uses->[$lines];
        $LineInfoHash{'Rotary'}     = $Rotary->[$lines];
        $LineInfoHash{'Sestmo'}     = $Sestmo->[$lines];
        $LineInfoHash{'Tmo'}        = $Tmo->[$lines];
        $LineInfoHash{'Esc'}        = $Esc->[$lines];
        $LineInfoHash{'Scrwid'}     = $Scrwid->[$lines];
        $LineInfoHash{'Scrlen'}     = $Scrlen->[$lines];
        $LineInfoHash{'Term'}       = $Term->[$lines];
        $LineInfoHash{'Loc'}        = $Loc->[$lines];
        $LineInfoHash{'Modem'}      = exists($LineModem{$Modem->[$lines]}) ? $LineModem{$Modem->[$lines]} : $Modem->[$lines];
        $LineInfoHash{'Flow'}       = exists($LineFlow{$Flow->[$lines]}) ? $LineFlow{$Flow->[$lines]} : $Flow->[$lines];
        $LineInfoHash{'Speedout'}   = $Speedout->[$lines];
        $LineInfoHash{'Speedin'}    = $Speedin->[$lines];
        $LineInfoHash{'Autobaud'}   = $Autobaud->[$lines];
        $LineInfoHash{'Type'}       = exists($LineTypes{$Type->[$lines]}) ? $LineTypes{$Type->[$lines]} : $Type->[$lines];
        $LineInfoHash{'Active'}     = $Active->[$lines];
        if ($Active->[$lines] == 1) {
            my $SesSession = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.8.' . $Number->[$lines]);
            my $SesLine    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.7.' . $Number->[$lines]);
            my $SesIdle    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.6.' . $Number->[$lines]);
            my $SesCur     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.5.' . $Number->[$lines]);
            my $SesName    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.4.' . $Number->[$lines]);
            my $SesAddr    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.3.' . $Number->[$lines]);
            my $SesDir     = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.2.' . $Number->[$lines]);
            my $SesType    = &_snmpgetnext($session, '1.3.6.1.4.1.9.2.9.3.1.1.' . $Number->[$lines]);

            my %SessionTypes = (
                1 => 'unknown',
                2 => 'PAD',
                3 => 'stream',
                4 => 'rlogin',
                5 => 'telnet',
                6 => 'TCP',
                7 => 'LAT',
                8 => 'MOP',
                9 => 'SLIP',
                10 => 'XRemote',
                11 => 'rshell'
            );
            my %SessionDir = (
                1 => 'unknown',
                2 => 'IN',
                3 => 'OUT'
            );
            my %SessionInfo;
            for my $sess (0..$#{$SesSession}) {
                my %SessionInfoHash;
                $SessionInfoHash{'Session'} = $SesSession->[$sess];
                $SessionInfoHash{'Line'}    = $SesLine->[$sess];
                $SessionInfoHash{'Idle'}    = $SesIdle->[$sess];
                $SessionInfoHash{'Cur'}     = $SesCur->[$sess];
                $SessionInfoHash{'Name'}    = $SesName->[$sess];
                $SessionInfoHash{'Addr'}    = $SesAddr->[$sess];
                $SessionInfoHash{'Dir'}     = exists($SessionDir{$SesDir->[$sess]}) ? $SessionDir{$SesDir->[$sess]} : $SesDir->[$sess];
                $SessionInfoHash{'Type'}    = exists($SessionTypes{$SesType->[$sess]}) ? $SessionTypes{$SesType->[$sess]} : $SesType->[$sess];
#                $SessionInfo{$SesSession->[$sess]} = \%SessionInfoHash
                push @{$SessionInfo{$Number->[$lines]}}, \%SessionInfoHash
            }
#            $LineInfoHash{'_SESSIONINFO_'} = \%SessionInfo
            $LineInfoHash{'_SESSIONINFO_'} = $SessionInfo{$Number->[$lines]}
        }
        $LineInfo{$Number->[$lines]} = bless \%LineInfoHash
    }
    return bless \%LineInfo, $class
}

sub line_info_sessions {
    my $self  = shift;
    return $self->{'_SESSIONINFO_'}
}

sub line_message {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my %params = (
        message => 'Test Message.',
        lines   => [-1]
    );

    my %args;
    if (@_ == 1) {
        ($params{'message'}) = @_
    } else {
        %args = @_;
        for (keys(%args)) {
            if (/^-?message$/i) {
                $params{'message'} = $args{$_}
            } elsif (/^-?line(?:s)?$/i) {
                if (!defined($params{'lines'} = _get_range($args{$_}))) {
                    return(undef)
                }
            }
        }
    }

    my $response;
    my @lines;
    for (@{$params{'lines'}}) {
          # Lines
        my $response = $session->set_request("1.3.6.1.4.1.9.2.9.4.0", INTEGER, $_);
          # Interval (reissue)
        $response = $session->set_request("1.3.6.1.4.1.9.2.9.5.0", INTEGER, 0);
          # Duration
        $response = $session->set_request("1.3.6.1.4.1.9.2.9.6.0", INTEGER, 0);
          # Text (256 chars)
        $response = $session->set_request("1.3.6.1.4.1.9.2.9.7.0", OCTET_STRING, $params{'message'});
          # Temp Banner (1=no 2=append)
        $response = $session->set_request("1.3.6.1.4.1.9.2.9.8.0", INTEGER, 1);
          # Send
        $response = $session->set_request("1.3.6.1.4.1.9.2.9.9.0", INTEGER, 1);
        if (defined($response)) {
            push @lines, $_
        } else {
            $LASTERROR = "Failed to send message to line $_";
            return(undef)
        }
    }
    # clear message
    $session->set_request("1.3.6.1.4.1.9.2.9.7.0", OCTET_STRING, "");
    if ($lines[0] == -1) { $lines[0] = "ALL" }
    return \@lines
}

sub line_numberof {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $response;
    if (!defined($response = $session->get_request( -varbindlist => ['1.3.6.1.4.1.9.2.9.1.0'] ))) {
        $LASTERROR = "Cannot retrieve number of lines";
        return(undef)
    } else {
        return $response->{'1.3.6.1.4.1.9.2.9.1.0'}
    }
}

sub memory_info {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $Name        = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.2');
    if (!defined($Name)) {
        $LASTERROR = "Cannot get memory info";
        return(undef)
    }
    my $Alternate   = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.3');
    my $Valid       = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.4');
    my $Used        = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.5');
    my $Free        = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.6');
    my $LargestFree = &_snmpgetnext($session, '1.3.6.1.4.1.9.9.48.1.1.1.7');

    my @MemInfo;
    for my $mem (0..$#{$Name}) {
        my %MemInfoHash;
        $MemInfoHash{'Name'}        = $Name->[$mem];
        $MemInfoHash{'Alternate'}   = $Alternate->[$mem];
        $MemInfoHash{'Valid'}       = ($Valid->[$mem] == 1) ? 'TRUE' : 'FALSE';
        $MemInfoHash{'Used'}        = $Used->[$mem];
        $MemInfoHash{'Free'}        = $Free->[$mem];
        $MemInfoHash{'LargestFree'} = $LargestFree->[$mem];
        $MemInfoHash{'Total'}       = $Used->[$mem] + $Free->[$mem];
        push @MemInfo, \%MemInfoHash
    }
    return \@MemInfo
}

sub proxy_ping {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $pp;
    foreach my $key (keys(%{$self})) {
        # everything but '_xxx_'
        $key =~ /^\_.+\_$/ and next;
        $pp->{$key} = $self->{$key}
    }

    my %params = (
        count => 1,
        host  => inet_ntoa((gethostbyname(hostname))[4]),
        size  => 64,
        wait  => 1
    );

    my %args;
    if (@_ == 1) {
        ($params{'host'}) = @_;
        if (defined(gethostbyname($params{'host'}))) {
            $params{'host'} = inet_ntoa((gethostbyname($params{'host'}))[4])
        } else {
            $LASTERROR = "Cannot resolve IP for $params{'host'}";
            return(undef)
        }
    } else {
        %args = @_;
        for (keys(%args)) {
            if ((/^-?host(?:name)?$/i) || (/^-?dest(?:ination)?$/i)) {
                $params{'host'} = $args{$_};
                if (defined(gethostbyname($params{'host'}))) {
                    $params{'host'} = inet_ntoa((gethostbyname($params{'host'}))[4])
                } else {
                    $LASTERROR = "Cannot resolve IP for $params{'host'}";
                    return(undef)
                }
            } elsif (/^-?size$/i) {
                if ($args{$_} =~ /^\d+$/) {
                    $params{'size'} = $args{$_}
                } else {
                    $LASTERROR = "Invalid size - $args{$_}";
                    return(undef)
                }
            } elsif (/^-?count$/i) {
                if ($args{$_} =~ /^\d+$/) {
                    $params{'count'} = $args{$_}
                } else {
                    $LASTERROR = "Invalid count - $args{$_}";
                    return(undef)
                }
            } elsif ((/^-?wait$/i) || (/^-?timeout$/i)) {
                if ($args{$_} =~ /^\d+$/) {
                    $params{'wait'} = $args{$_}
                } else {
                    $LASTERROR = "Invalid wait time - $args{$_}";
                    return(undef)
                }
            } elsif (/^-?vrf(?:name)?$/i) {
                $params{'vrf'} = $args{$_}
            }
        }
    }
    $pp->{_PROXYPING_}{'_params_'} = \%params;

    my $instance = int(rand(1024)+1024);
      # Prepare object by clearing row
    my $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance, INTEGER, 6);
    if (!defined($response)) {
        $LASTERROR = "NOT SUPPORTED";
        return(undef)
    }

    # Convert destination to Hex equivalent
    my $dest;
    for (split(/\./, $params{'host'})) {
        $dest .= sprintf("%02x",$_)
    }

      # ciscoPingEntryStatus (5 = createAndWait, 6 = destroy)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance, INTEGER, 6);
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance, INTEGER, 5);
      # ciscoPingEntryOwner (<anyname>)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.15.' . $instance, OCTET_STRING, __PACKAGE__);
      # ciscoPingProtocol (1 = IP)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.2.' . $instance, INTEGER, 1);
      # ciscoPingAddress (NOTE: hex string, not regular IP)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.3.' . $instance, OCTET_STRING, pack('H*', $dest));
      # ciscoPingPacketTimeout (in ms)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.6.' . $instance, INTEGER32, $params{'wait'}*100);
      # ciscoPingDelay (Set gaps (in ms) between successive pings)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.7.' . $instance, INTEGER32, $params{'wait'}*100);
      # ciscoPingPacketCount
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.4.' . $instance, INTEGER, $params{'count'});
      # ciscoPingPacketSize (protocol dependent)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.5.' . $instance, INTEGER, $params{'size'});

    if (exists($params{'vrf'})) {
          # ciscoPingVrfName (<name>)
        $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.17.' . $instance, OCTET_STRING, $params{'vrf'})
    }
      # Verify ping is ready (ciscoPingEntryStatus = 2)
    $response = $session->get_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance);
    if (defined($response->{'1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance})) {
        if ($response->{'1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance} != 2) {
            $LASTERROR = "Ping not ready";
            return(undef)
        }
    } else {
        $LASTERROR = "NOT SUPPORTED (after setup)";
        return(undef)
    }

      # ciscoPingEntryStatus (1 = activate)
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance, INTEGER, 1);

    # Wait sample interval
    sleep $params{'wait'};

      # Get results
    $response = $session->get_table('1.3.6.1.4.1.9.9.16.1.1.1');
    $pp->{'_PROXYPING_'}{'Sent'}     = $response->{'1.3.6.1.4.1.9.9.16.1.1.1.9.' . $instance}  || 0;
    $pp->{'_PROXYPING_'}{'Received'} = $response->{'1.3.6.1.4.1.9.9.16.1.1.1.10.' . $instance} || 0;
    $pp->{'_PROXYPING_'}{'Minimum'}  = $response->{'1.3.6.1.4.1.9.9.16.1.1.1.11.' . $instance} || 0;
    $pp->{'_PROXYPING_'}{'Average'}  = $response->{'1.3.6.1.4.1.9.9.16.1.1.1.12.' . $instance} || 0;
    $pp->{'_PROXYPING_'}{'Maximum'}  = $response->{'1.3.6.1.4.1.9.9.16.1.1.1.13.' . $instance} || 0;

      # destroy entry
    $response = $session->set_request('1.3.6.1.4.1.9.9.16.1.1.1.16.' . $instance, INTEGER, 6);
    return bless $pp, $class
}

sub proxy_ping_sent {
    my $self = shift;
    return $self->{'_PROXYPING_'}{'Sent'}
}

sub proxy_ping_received {
    my $self = shift;
    return $self->{'_PROXYPING_'}{'Received'}
}

sub proxy_ping_minimum {
    my $self = shift;
    return $self->{'_PROXYPING_'}{'Minimum'}
}

sub proxy_ping_average {
    my $self = shift;
    return $self->{'_PROXYPING_'}{'Average'}
}

sub proxy_ping_maximum {
    my $self = shift;
    return $self->{'_PROXYPING_'}{'Maximum'}
}

sub system_info {
    my $self  = shift;
    my $class = ref($self) || $self;

    my $session = $self->{'_SESSION_'};

    my $sysinfo;
    foreach my $key (keys(%{$self})) {
        # everything but '_xxx_'
        $key =~ /^\_.+\_$/ and next;
        $sysinfo->{$key} = $self->{$key}
    }

    my $response = &_snmpgetnext($session, '1.3.6.1.2.1.1');
    if (defined($response)) {

        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Description'} = $response->[0] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'ObjectID'}    = $response->[1] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Uptime'}      = $response->[2] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Contact'}     = $response->[3] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Name'}        = $response->[4] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Location'}    = $response->[5] }
        if (defined($response->[0])) { $sysinfo->{'_SYSINFO_'}{'Services'}    = $response->[6] }

        return bless $sysinfo, $class
    } else {
        $LASTERROR = "Cannot read system MIB";
        return(undef)
    }
}

sub system_info_description {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'Description'}
}

sub system_info_objectID {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'ObjectID'}
}

sub system_info_uptime {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'Uptime'}
}

sub system_info_contact {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'Contact'}
}

sub system_info_name {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'Name'}
}

sub system_info_location {
    my $self = shift;
    return $self->{'_SYSINFO_'}{'Location'}
}

sub system_info_services {
    my ($self, $arg) = @_;

    if (defined($arg) && ($arg >= 1)) {
        return $self->{'_SYSINFO_'}{'Services'}
    } else {
        my %Services = (
            1  => 'Physical',
            2  => 'Datalink',
            4  => 'Network',
            8  => 'Transport',
            16 => 'Session',
            32 => 'Presentation',
            64 => 'Application'
        );
        my @Svcs;
        for (sort {$b <=> $a} (keys(%Services))) {
            push @Svcs, $Services{$_} if ($self->{'_SYSINFO_'}{'Services'} & int($_))
        }
        return \@Svcs
    }
}

sub system_info_osversion {
    my $self = shift;

    if ($self->{'_SYSINFO_'}{'Description'} =~ /Version ([^ ,\n\r]+)/) {
        return $1
    } else {
        return "Cannot determine OS Version"
    }
}

########################################################
# Subroutines
########################################################

sub password_decrypt {

    my $self = shift;
    my $class = ref($self) || $self;

    my $passwd;

    if ($self ne __PACKAGE__) {
        $passwd = $self
    } else {
        ($passwd) = @_
    }

    if (($passwd =~ /^[\da-f]+$/i) && (length($passwd) > 2)) {
        if (!(length($passwd) & 1)) {
            my $dec = "";
            my ($s, $e) = ($passwd =~ /^(..)(.+)/o);

            for (my $i = 0; $i < length($e); $i+=2) {
                # If we move past the end of the XOR key, reset
                if ($s > $#xlat) { $s = 0 }
                $dec .= sprintf "%c",hex(substr($e,$i,2))^$xlat[$s++]
            }
            return $dec
        }
    }
    $LASTERROR = "Invalid Password: $passwd";
    return(0)
}

sub password_encrypt {

    my $self = shift;
    my $class = ref($self) || $self;

    my ($cleartxt, $index);

    if ($self ne __PACKAGE__) {
        $cleartxt = $self;
        ($index) = @_
    } else {
        ($cleartxt, $index) = @_
    }

    my $start = 0;
    my $end = $#xlat;

    if (defined($index)) {
        if ($index =~ /^\d+$/) {
            if (($index < 0) || ($index > $#xlat)) {
                $LASTERROR = "Index out of range 0-$#xlat: $index";
                return(0)
            } else {
                $start = $index;
                $end   = $index
            } 
        } elsif ($index eq "") {
            # Do them all - currently set for that.
        } else {
            my $random = int(rand($#xlat + 1));
            $start = $random;
            $end   = $random
        }
    }

    my @passwds;
    for (my $j = $start; $j <= $end; $j++) {
        my $encrypt = sprintf "%02i", $j;
        my $s       = $j;

        for (my $i = 0; $i < length($cleartxt); $i++) {
            # If we move past the end of the XOR key, reset
            if ($s > $#xlat) { $s = 0 }
            $encrypt .= sprintf "%02X", ord(substr($cleartxt,$i,1))^$xlat[$s++]
        }
        push @passwds, $encrypt
    }
    return \@passwds
}

sub close {
    my $self = shift;
    $self->{_SESSION_}->close();
}

sub error {
    return($LASTERROR)
}

########################################################
# End Public Module
########################################################

########################################################
# Start Private subs
########################################################

sub _get_range {

    my ($opt) = @_;

    # If argument, it must be a number range in the form:
    #  1,9-11,7,3-5,15
    if ($opt !~ /^\d+([\,\-]\d+)*$/) {
        $LASTERROR = "Incorrect range format";
        return(undef)
    }

    my (@option, @temp, @ends);

    # Split the string at the commas first to get:  1 9-11 7 3-5 15
    @option = split(/,/, $opt);

    # Loop through remaining values for dashes which mean all numbers inclusive.
    # Thus, need to expand ranges and put values in array.
    for $opt (@option) {

        # If value has a dash '-', split and add 'missing' numbers.
        if ($opt =~ /-/) {

            # Ends are start and stop number of range.  For example, $opt = 9-11:
            # $ends[0] = 9
            # $ends[1] = 11
            @ends = split(/-/, $opt);

            for ($ends[0]..$ends[1]) {
                push @temp, $_
            }

        # No dash '-', move on
        } else {
            push @temp, $opt
        }
    }
    # return the sorted values of the temp array
    @temp = sort { $a <=> $b } (@temp);
    return \@temp
}

sub _snmpgetnext {

    my ($session, $oid) = @_;

    my (@oids, @vals);
    my $base = $oid;
    my $result = 0;

    while (defined($result = $session->get_next_request( -varbindlist => [$oid] ))) {
        my ($o, $v) = each(%{$result});
        if (oid_base_match($base, $o)) {
            push @vals, $v;
            push @oids, $o;
            $oid = $o
        } else {
            last
        }
    }
    if ($#vals == -1) {
        return(undef)
    } else {
        return (\@oids, \@vals)
    }
}


########################################################
# End Private subs
########################################################

1;

__END__

########################################################
# Start POD
########################################################

=head1 NAME

Cisco::Management - Interface for Cisco Management

=head1 SYNOPSIS

  use Cisco::Management;

=head1 DESCRIPTION

Cisco::Management is a class implementing several management functions 
for Cisco devices - mostly via SNMP.  Cisco::Management uses the 
Net::SNMP module to do the SNMP calls.

=head1 METHODS

=head2 new() - create a new Cisco::Management object

  my $cm = new Cisco::Management([OPTIONS]);

or

  my $cm = Cisco::Management->new([OPTIONS]);

Create a new Cisco::Management object with OPTIONS as optional parameters.
Valid options are:

  Option     Description                            Default
  ------     -----------                            -------
  -hostname  Remote device to connect to            localhost
  -port      Port to connect to                     161
  -community SNMP read/write community string       private
  -timeout   Timeout to wait for request in seconds 10

=head2 session() - return Net::SNMP session object

  $session = $cm->session;

Return the Net::SNMP session object created by the Cisco::Management 
new() method.  This is useful to call Net::SNMP related methods without 
having to create a new Net::SNMP object.  For example:

  my $cm = new Cisco::Management(-host      => 'router1',
                                 -community => 'snmpRW'
  );
  my $session = $cm->session();
  $session->get_request('1.3.6.1.2.1.1.4.0');

In this case, the C<get_request> call is a method provided by the 
Net::SNMP module that can be accessed directly via the C<$session> 
object returned by the C<$cm-E<gt>session()> method.

=head2 close() - close session

  $cm->close;

Close the Cisco::Management session.

=head2 error() - print last error

  printf "Error: %s\n", Net::Syslogd->error;

Return last error.

=head2 Configuration Management Options

The following methods are for configuration file management.

=head2 config_copy() - configuration file management

  my $cc = $cm->config_copy([OPTIONS]);

Manage configuration files.  Options allow for TFTP upload or download 
of running-config or startup-config and a copy running-config to 
startup-config or vice versa.  Valid options are:

  Option     Description                            Default
  ------     -----------                            -------
  -tftp      TFTP server address                    localhost
  -source    'startup-config', 'running-config'     'running-config'
             or filename on TFTP server
  -dest      'startup-config', 'running-config'     'startup-config'
             or filename for TFTP server
  -catos     Catalyst OS flag                       0

The default behavior with no options is C<copy running-config 
startup-config>.

This method implements the C<CISCO-CONFIG-COPY-MIB> for configuration 
file management.  If these operations fail, the older method in 
C<OLD-CISCO-SYS-MIB> is tried.  All Catalyst OS operations are performed 
against the C<CISCO-STACK-MIB>.

B<NOTE:>  Use care when performing TFTP upload to startup-config.  This 
B<MUST> be a B<FULL> configuration file as the config file is B<NOT>
merged, but instead B<OVERWRITES> the startup-config.

Allows the following methods to be called.

=head3 config_copy_starttime() - return config copy start time

  $cc->config_copy_starttime();

Return the start time of the configuration copy operation relative to 
system uptime.

=head3 config_copy_endtime() - return config copy end time

  $cc->config_copy_endtime();

Return the end time of the configuration copy operation relative to 
system uptime.

=head2 CPU Info

The following methods are for CPU utilization.  These methods 
implement the C<CISCO-PROCESS-MIB> and C<OLD-CISCO-SYS-MIB>.

=head2 cpu_info() - return CPU utilization info

  my $cpuinfo = $cm->cpu_info();

Populate a data structure with CPU information.  If successful, 
returns pointer to array containing CPU information.

  $cpuinfo->[0]->{'Name', '5sec', '1min', ...}
  $cpuinfo->[1]->{'Name', '5sec', '1min', ...}
  ...
  $cpuinfo->[n]->{'Name', '5sec', '1min', ...}

=head2 Interface Options

The following methods are for interface management.  These methods 
implement the C<IF-MIB>.

=head2 interface_getbyindex() - get interface name by ifIndex

  my $line = $cm->interface_getbyindex([OPTIONS]);

Resolve an ifIndex the full interface name.  Called with one argument, 
interpreted as the interface ifIndex to resolve.

  Option     Description                            Default
  ------     -----------                            -------
  -index     The ifIndex to resolve                 -REQUIRED-

Returns the full interface name string.

=head2 interface_getbyname() - get interface name/ifIndex by string

  my $name = $cm->interface_getbyname([OPTIONS]);

Get the full interface name or ifIndex number by the Cisco 'shortcut' 
name.  For example, 'gig0/1' or 's0/1' resolves to 'GigabitEthernet0/1' 
and 'Serial0/1' respectively.  Called with one argument, interpreted 
as the interface string to resolve.

  Option     Description                            Default
  ------     -----------                            -------
  -interface String to resolve                      -REQUIRED-
  -index     Return ifIndex number instead (flag)   0

Returns the full interface name string or ifIndex (if -index flag).

=head2 interface_info() - return interface info

  my $ifs = $cm->interface_info();

Populate a data structure with interface information including IP 
information if found.  If successful, returns pointer to hash 
containing interface information.

Interface information consists of the following MIB entries (exludes 
counter-type interface metrics):

  Index
  Description
  Type
  MTU
  Speed
  Duplex *
  PhysAddress
  AdminStatus
  OperStatus
  LastChange

B<NOTE:>  Duplex is found in the C<EtherLike-MIB>.

  $ifs->{1}->{'Index', 'Description', ...}
  $ifs->{2}->{'Index', 'Description', ...}
  ...
  $ifs->{n}->{'Index', 'Description', ...}

IP information can be accessed directly or with the following method.

=head3 interface_info_ip() - return IP info on current interface

  my $ips = $ifs->{n}->interface_info_ip();

Return a reference to an array containing the IP info for the current 
interface.

  my $ifs = $cm->interface_info();
  ...
  if (defined(my $ips = $ifs->{$_}->interface_info_ip())) {
      $ips->[0]->{'IPAddress', 'IPMask'}
      ...
      $ips->[n]->{'IPAddress', 'IPMask'}

=head2 interface_updown() - admin up/down interface

  my $line = $cm->interface_updown([OPTIONS]);

Admin up or down the interface.  With no arguments, all interfaces are 
made admin up.

  Option     Description                            Default
  ------     -----------                            -------
  -operation 'up' or 'down'                         'up'
  -interface ifIndex or range of ifIndex (, and -)  (all)

To specify individual interfaces, provide their number:

  my $line = $cm->line_clear(2);

Admin up ifIndex 2.  To specify a range of interfaces, provide a 
range:

  my $line = $cm->line_clear(
                             operation  => 'down',
                             interfaces => '2-4,6,9-11'
                            );

Admin down ifIndex 2 3 4 6 9 10 11.

Returns a pointer to an array containing the interfaces admin up/down 
if successful.

=head2 Line Options

The following methods are for line management.  Lines on Cisco devices 
refer to console, auxillary and terminal lines for user interaction.  
These methods implement the C<OLD-CISCO-TS-MIB> which is not available 
on some newer forms of IOS.

=head2 line_clear() - clear connection to line

  my $line = $cm->line_clear([OPTIONS]);

Clear the line (disconnect interactive session).  With no arguments, 
all lines are cleared.  To specify individual lines, provide their 
number:

  my $line = $cm->line_clear(2);

or

  my $line = $cm->line_clear(lines => 2);

Clear line 2.  To specify a range of lines, provide a range:

  my $line = $cm->line_clear('2-4,6,9-11');

or

  my $line = $cm->line_clear(range => '2-4,6,9-11');

Clear lines 2 3 4 6 9 10 11.

Returns a pointer to an array containing the lines cleared if 
successful.

=head2 line_info() - return line info

  my $line = $cm->line_info();

Populate a data structure with line information including active 
sessions if found.  If successful, returns pointer to hash containing 
line information.

  $line->{0}->{'Number', 'TimeActive', ...}
  $line->{1}->{'Number', 'TimeActive', ...}
  ...
  $line->{n}->{'Number', 'TimeActive', ...}

If the line is active, then session information is returned also.  It 
can be accessed directly or with the following method.

=head3 line_info_sessions() - return session info on current line

  my $session = $line->{n}->line_info_sessions();

Return a reference to an array containing the session info for the 
current line.  Should be called on active line as in the following.

  my $line = $cm->line_info();
  ...
  if ($line->{$_}->{'Active'} == 1) {
      my $sessions = $line->{$_}->line_info_sessions()
      $sessions->[0]->{'Session', 'Type', 'Dir' ...}
      ...
      $sessions->[n]->{'Session', 'Type', 'Dir' ...}

=head2 line_message() - send message to line

  my $line = $cm->line_message([OPTIONS]);

Send a message to the line.  With no arguments, a "Test Message" is 
sent to all lines.  If 1 argument is provided, it is interpreted as 
the message to send to all lines.  Valid options are:

  Option     Description                            Default
  ------     -----------                            -------
  -lines     Line or range of lines (, and -)       (all)
  -message   Double-quote delimited string          "Test Message"

Returns a pointer to an array containing the lines messaged if 
successful.

=head2 line_numberof() - return number of lines

  my $line = $cm->line_numberof();

Returns the number of lines on the device.

=head2 Memory Info

The following methods are for memory utilization.  These methods 
implement the C<CISCO-MEMORY-POOL-MIB>.

=head2 memory_info() - return memory utilization info

  my $meminfo = $cm->memory_info();

Populate a data structure with memory information.  If successful, 
returns pointer to array containing memory information.

  $meminfo->[0]->{'Name', 'Used', 'Free', ...}
  $meminfo->[1]->{'Name', 'Used', 'Free', ...}
  ...
  $meminfo->[n]->{'Name', 'Used', 'Free', ...}

=head2 Proxy Ping

The following methods are for proxy ping.  These methods implement the 
C<CISCO-PING-MIB>.

=head2 proxy_ping() - execute proxy ping

  my $ping = $cm->proxy_ping([OPTIONS]);

Send proxy ping from the object defined in C<$cm> to the provided 
destination.  Called with no options, sends the proxy ping to the 
localhost.  Called with one argument, interpreted as the destination 
to ping.  Valid options are:

  Option     Description                            Default
  ------     -----------                            -------
  -host      Destination to send proxy ping to      (localhost)
  -count     Number of pings to send                1
  -size      Size of the ping packets in bytes      64
  -wait      Time to wait for replies in seconds    1
  -vrf       VRF name to source pings from          [none]

Allows the following methods to be called.

=head3 proxy_ping_sent() - return number of pings sent

  $ping->config_copy_sent();

Return the number of pings sent in the current proxy ping execution.

=head3 proxy_ping_received() - return number of pings received

  $ping->config_copy_received();

Return the number of pings received in the current proxy ping execution.

=head3 proxy_ping_minimum() - return minimum round trip time

  $ping->config_copy_minimum();

Return the minimum round trip time in milliseconds of pings sent and 
received in the current proxy ping execution.

=head3 proxy_ping_average() - return average round trip time

  $ping->config_copy_average();

Return the average round trip time in milliseconds of pings sent and 
received in the current proxy ping execution.

=head3 proxy_ping_maximum() - return maximum round trip time

  $ping->config_copy_maximum();

Return the maximum round trip time in milliseconds of pings sent and 
received in the current proxy ping execution.

=head2 System Info

The following methods interface with the System MIB defined in 
C<SNMPv2-MIB>.

=head2 system_info() - populate system info data structure.

  my $sysinfo = $cm->system_info();

Retrieve the system MIB information from the object defined in C<$cm>.  

Allows the following methods to be called.

=head3 system_info_description() - return system description

  $sysinfo->system_info_description();

Return the system description from the system info data structure.

=head3 system_info_objectID() - return system object ID

  $sysinfo->system_info_objectID();

Return the system object ID from the system info data structure.

=head3 system_info_uptime() - return system uptime

  $sysinfo->system_info_uptime();

Return the system uptime from the system info data structure.

=head3 system_info_contact() - return system contact

  $sysinfo->system_info_contact();

Return the system contact from the system info data structure.

=head3 system_info_name() - return system name

  $sysinfo->system_info_name();

Return the system name from the system info data structure.

=head3 system_info_location() - return system location

  $sysinfo->system_info_location();

Return the system location from the system info data structure.

=head3 system_info_services() - return system services

  $sysinfo->system_info_services([1]);

Return a pointer to an array containing the names of the system 
services from the system info data structure.  For the raw number, 
use the optional boolean argument.

=head3 system_info_osversion() - return system OS version

  $sysinfo->system_info_osversion();

Return the system OS version as parsed from the sysDescr OID.

=head1 SUBROUTINES

Password subroutines are for decrypting and encrypting 
Cisco type 7 passwords.  The algorithm is freely available on the 
Internet on several sites; thus, I can/will B<not> take credit for it.

=head2 password_decrypt() - decrypt a Cisco type 7 password

  my $passwd = Cisco::Password->password_decrypt('00071A150754');

Where C<00071A150754> is the encrypted Cisco password in this example.

=head2 password_encrypt() - encrypt a Cisco type 7 password

  my $passwd = Cisco::Password->password_encrypt('cleartext'[,# | *]);
  print "$_\n" for (@{$passwd});

Where C<cleartext> is the clear text string to encrypt.  The second 
optional argument is a number in the range of 0 - 52 inclusive or 
random text.

This sub returns a pointer to an array.  The array is constructed based 
on the second argument to C<password_encrypt>.  

  Option  Description            Action
  ------  -----------            -------
          No argument provided   Return all 53 possible encryptions.
  #       Number 0-52 inclusive  Return password encrypted with # index.
  (other) Random text            Return a random password.

B<NOTE:>  Cisco routers by default only seem to use the first 16 indexes 
(0 - 15) to encrypt passwords.  You notice this by looking at the first 
two characters of any type 7 encrypted password in a Cisco router 
configuration.  However, testing on IOS 12.x and later show that manually 
entering a password encrypted with a higer index (generated from this 
script) to a Cisco configuration will not only be allowed, but will 
function normally for authentication.  This may be a form of "security 
through obscurity" given that some older Cisco password decrypters don't 
use the entire translation index and limit 'valid' passwords to those 
starting with the fist 16 indexes (0 - 15).  Using passwords with an 
encryption index of 16 - 52 inclusive I<may> render older Cisco password 
decrypters useless.

Additionally, the Cisco router command prompt seems to be limited to 254 
characters, making the largest password 250 characters (254 - 4 
characters for the C<pas > (followed by space) command to enter the 
password).  

=head1 EXPORT

None by default.

=head1 EXAMPLES

=head2 Configuration File Management

This example connects to a device (router1) with SNMP read/write 
community (readwrite) and performs a configuration file upload 
via TFTP and if successful, a C<copy run start>.

  use strict;
  use Cisco::Management;

  my $cm = Cisco::Management->new(
                            hostname  => 'router1',
                            community => 'readwrite'
                           );

  if (defined(my $conf = $cm->config_copy(
                                          -tftp   => '10.10.10.1',
                                          -source => 'foo.confg',
                                          -dest   => 'run'
                                         ))) {
      printf "START: %s\n", $conf->config_copy_starttime();
      printf "END  : %s\n", $conf->config_copy_endtime();

      # Only if above successful, 
      # Default action is "copy run start"
      if (defined($conf = $cm->config_copy())) {
          print "copy run start\n"
      } else {
          printf "Error: %s\n", Cisco::Management->error
      }
  } else {
      printf "Error: %s\n", Cisco::Management->error
  }

  $cm->close();

=head2 Cisco Password Decrypter

This example implements a simple Cisco password decrypter.

  use Cisco::Management;

  if (!defined($ARGV[0])) {
      print "Usage:  $0 encypted_password\n";
      exit 1
  }

  if (my $passwd = Cisco::Management->password_decrypt($ARGV[0])) {
      print "$passwd\n";
  } else {
      printf "Error - %s\n", Cisco::Management->error
  }

=head1 LICENSE

This software is released under the same terms as Perl itself.
If you don't know what that means visit L<http://perl.com/>.

=head1 AUTHOR

Copyright (C) Michael Vincent 2010

L<http://www.VinsWorld.com>

All rights reserved

=cut
