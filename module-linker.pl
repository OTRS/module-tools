#!/usr/bin/perl
# --
# module-linker.pl - script for linking OTRS modules into framework root
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

## nofilter(TidyAll::Plugin::OTRS::Perl::Require)

use File::Find;
use Cwd;

my $Action = shift || '';
if ( $Action !~ m{^(install|uninstall)$} ) {
    Usage("ERROR: action (ARG0) must be either 'install' or 'uninstall'!");
    exit 2;
}

if ( $^O =~ 'MSWin' ) {

    require Win32;

    # mklink is only supported on Vista, Win2008 or later.
    my ( $VersionString, $VersionMajor, $VersionMinor, $VersionBuild, $VersionID )
        = Win32::GetOSVersion();
    if ( $VersionID < 2 || ( $VersionID = 2 && $VersionMajor < 6 ) ) {
        print
            "If you want to use the module-linker script on Windows, you should use Vista, Win2008 or later";
        exit 2;
    }

    # in order for mklink to work, UAC must be elevated.
    if ( !Win32::IsAdminUser() ) {
        print "To be able to create symlinks, you'll have to start the script with UAC enabled.\n";
        print "(right-click CMD, select \'Run as administrator\').\n";
        exit 2;
    }
}

my $Directory = getcwd();

my $Source = shift;
if ( !defined $Source || !-d $Source ) {
    Usage("ERROR: invalid source module path '$Source'");
    exit 2;
}
if ( substr( $Source, 0, 1 ) ne '/' ) {
    $Source = "$Directory/$Source";
    print "NOTICE: using absolute module path '$Source'\n";
}

my $Dest = shift;
if ( !defined $Dest || !-d $Dest ) {
    Usage("ERROR: invalid framework-root path '$Dest'");
    exit 2;
}
if ( substr( $Dest, 0, 1 ) ne '/' ) {
    $Dest = "$Directory/$Dest";
    print "NOTICE: using absolute framework root path '$Dest'\n";
}

# remove any trailing slashes from source and destination paths
if ( substr( $Source, -1, 1 ) eq '/' ) {
    chop $Source;
}
if ( substr( $Dest, -1, 1 ) eq '/' ) {
    chop $Dest;
}

if ( $Action eq 'install' ) {
    find( \&InstallHandler, $Source );
}
elsif ( $Action eq 'uninstall' ) {
    find( \&UninstallHandler, $Source );
}

sub Usage {
    my ($Message) = @_;

    print STDERR <<"End-of-Here";
$Message

USAGE:
    $0 install <source-module-path> <otrs-framework-root>
or
    $0 uninstall <source-module-path> <otrs-framework-root>
End-of-Here
    return;
}

sub InstallHandler {

    # skip (i.e. do not enter) folders named 'CVS' or '.svn'
    if ( m{^(CVS|\.svn)$} && -d ) {
        $File::Find::prune = 1;
        return;
    }

    # skip anything that starts with a dot (except for '.')
    # [this e.g. bypasses Eclipse project files like '.includepath' and '.project']
    if (m{^\..+$}) {
        $File::Find::prune = 1;
        return;
    }

    #   print "handling '$File::Find::name'\n";

    # compute full target name (by replacing source- with destination-path)
    my $Target = $File::Find::name;
    $Target =~ s{^$Source}{$Dest};

    if ( -d $File::Find::name ) {
        return if -d $Target;
        print "NOTICE: mkdir $Target\n";
        mkdir($Target);
    }
    else {
        if ( -l $Target ) {

            # skip if already linked correctly
            if ( readlink($Target) eq $File::Find::name ) {
                print "NOTICE: link from $Target is ok\n";
                return;
            }

            # remove link to some different file
            ## no critic
            unlink($Target) or die "ERROR: Can't unlink symlink: $Target";
            ## use critic
        }

        # backup target if it already exists as a file
        if ( -f $Target ) {
            if ( rename( $Target, "$Target.old" ) ) {
                print "NOTICE: created backup for original file: $Target.old\n";
            }
            else {
                die "ERROR: Can't rename $Target to $Target.old: $!";
            }
        }

        # link source into target
        if ( $^O =~ 'MSWin' ) {
            $Target =~ s/\//\\/g;
            my $Source = $File::Find::name;
            $Source =~ s/\//\\/g;
            if ( !-e $File::Find::name ) {
                die "ERROR: No such source file: ${File::Find::name}";
            }
            system("mklink $Target $Source");
            print "NOTICE: Link: $Source\n";
            print "NOTICE:    -> $Target\n";
        }
        else {    # not Win32
            if ( !-e $File::Find::name ) {
                die "ERROR: No such source file: ${File::Find::name}";
            }
            elsif ( !symlink( $File::Find::name, $Target ) ) {
                die "ERROR: Can't link ${File::Find::name} to $Target: $!";
            }
            else {
                print "NOTICE: Link: ${File::Find::name}\n";
                print "NOTICE:    -> $Target\n";
            }
        }
    }
    return 1;
}

sub UninstallHandler {

    # skip (i.e. do not enter) folders named 'CVS' or '.svn'
    if ( m{^(CVS|\.svn)$} && -d ) {
        $File::Find::prune = 1;
        return;
    }

    # skip anything that starts with a dot (except for '.')
    # [this e.g. bypasses Eclipse project files like '.includepath' and '.project']
    if (m{^\..+$}) {
        $File::Find::prune = 1;
        return;
    }

    #   print "handling '$File::Find::name'\n";

    # compute full target name (by replacing source- with destination-path)
    my $Target = $File::Find::name;
    $Target =~ s{^$Source}{$Dest};

    return if -d $File::Find::name;

    if ( -l $Target ) {

        # remove link only if it points to our current source
        if ( readlink($Target) eq $File::Find::name ) {
            ## no critic
            unlink($Target) or die "ERROR: Can't unlink symlink: $Target";
            ## use critic
            print "NOTICE: link from $Target removed\n";
        }

        # restore target if there is a backup
        if ( -f "$Target.old" ) {
            if ( rename( "$Target.old", $Target ) ) {
                print "NOTICE: Restored original file: $Target\n";
            }
            else {
                die "ERROR: Can't rename $Target.old to $Target: $!";
            }
        }
    }
    return 1;
}

exit 0;
