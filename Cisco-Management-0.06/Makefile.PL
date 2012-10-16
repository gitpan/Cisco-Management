use 5.006001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cisco::Management',
    VERSION_FROM      => 'lib/Cisco/Management.pm', # finds $VERSION
    EXE_FILES         => ['bin/cisco-conf.pl',
                          'bin/cisco-info.pl',
                          'bin/cisco-intf.pl',
                          'bin/cisco-line.pl',
                          'bin/cisco-pass.pl',
                          'bin/cisco-ping.pl'],
    PREREQ_PM         => {Test::Simple => 0, 
                          Net::SNMP => 0,
                          Socket => 0,
                          Net::IPv6Addr => 0.2,
                          Sys::Hostname => 0 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Cisco/Management.pm', # retrieve abstract from module
       AUTHOR         => 'Michael Vincent <vin at vinsworld dot com>') : ()),
);
