#!/usr/bin/perl -w
# --
# module-tools/module-linker.pl
#   - script for linking OTRS modules into framework root
# Copyright (C) 2001-2007 OTRS GmbH, http://otrs.org/
# --
# $Id: module-linker.pl,v 1.1 2007-10-16 09:15:16 ot Exp $
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# --

use strict;
use warnings;

use File::Find;

my $Action = shift || '';
if ($Action !~ m{^(install|uninstall)$}) {
    Usage("ERROR: action (ARG0) must be either 'install' or 'uninstall'!");
    exit 2;
}

my $Source = shift;
if (!defined $Source || !-d $Source) {
    Usage("ERROR: invalid source module path '$Source'");
    exit 2;
}
if (substr($Source, 0, 1) ne '/') {
    $Source = "$ENV{PWD}/$Source";
    print "NOTICE: using absolute module path '$Source'\n";
}

my $Dest = shift;
if (!defined $Dest || !-d $Dest) {
    Usage("ERROR: invalid framework-root path '$Dest'");
    exit 2;
}
if (substr($Dest, 0, 1) ne '/') {
    $Dest = "$ENV{PWD}/$Dest";
    print "NOTICE: using absolute framework root path '$Dest'\n";
}

# remove any trailing slashes from source and destination paths
if (substr($Source, -1, 1) eq '/') {
    chop $Source;
}
if (substr($Dest, -1, 1) eq '/') {
    chop $Dest;
}

if ($Action eq 'install') {
    find(\&InstallHandler, $Source);
}
elsif ($Action eq 'uninstall') {
    find(\&UninstallHandler, $Source);
}

sub Usage {
    my ( $Message ) = @_;

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
    if (m{^(CVS|\.svn)$} && -d) {
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

    if (-d $File::Find::name) {
        return if -d $Target;
        print "NOTICE: mkdir $Target\n";
        mkdir($Target);
    }
    else {
        if (-l $Target) {
            # skip if already linked correctly
            if (readlink($Target) eq $File::Find::name) {
                print "NOTICE: link from $Target is ok\n";
                return;
            }

            # remove link to some different file
            unlink($Target) or die "ERROR: Can't unlink symlink: $Target";
        }

        # backup target if it already exists as a file
        if (-f $Target) {
            if (rename($Target, "$Target.old")) {
                print "NOTICE: created backup for original file: $Target.old\n";
            }
            else {
                die "ERROR: Can't rename $Target to $Target.old: $!";
            }
        }

        # link source into target
        if (!-e $File::Find::name) {
            die "ERROR: No such source file: ${File::Find::name}";
        }
        elsif (!symlink($File::Find::name, $Target)) {
            die "ERROR: Can't link ${File::Find::name} to $Target: $!";
        }
        else {
            print "NOTICE: Link: ${File::Find::name}\n";
            print "NOTICE:    -> $Target\n";
        }
    }
    return 1;
}

sub UninstallHandler {

    # skip (i.e. do not enter) folders named 'CVS' or '.svn'
    if (m{^(CVS|\.svn)$} && -d) {
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

    if (-l $Target) {
        # remove link only if it points to our current source
        if (readlink($Target) eq $File::Find::name) {
            unlink($Target) or die "ERROR: Can't unlink symlink: $Target";
            print "NOTICE: link from $Target removed\n";
        }

        # restore target if there is a backup
        if (-f "$Target.old") {
            if (rename("$Target.old", $Target)) {
                print "NOTICE: Restored original file: $Target\n";
            }
            else {
                die "ERROR: Can't rename $Target.old to $Target: $!";
            }
        }
    }
    return 1;
}

=head1 NAME

module-linker.pl - simplified reimplementation of link.pl and remove-links.pl
based on File::Find

=head1 SYNOPSIS

module-linker.pl install <source-module-folder> <otrs-folder>
or
module-linker.pl uninstall <source-module-folder> <otrs-folder>

This script either installs a given OTRS module into the OTRS framework (by creating
appropriate links) or uninstalls the module (by removing those links again).

The intention of this reimplementation is to have simpler code and to make the
script slightly more robust against unintended inclusion of unwanted files,
e.g. files contained in repository meta folders ('CVS' or '.svn') and IDE-specific
files (.project and the like).

Please send any questions, suggestions & complaints to <ot@otrs.com>

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see http://www.gnu.org/licenses/gpl.txt.

=head1 VERSION

$Revision: 1.1 $

=cut
