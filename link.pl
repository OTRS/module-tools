#!/usr/bin/perl -w
# --
# module-tools/link.pl
#   - script for linking OTRS modules into framework root
# Copyright (C) 2001-2009 OTRS AG, http://otrs.org/
# --
# $Id: link.pl,v 1.12 2009-07-03 11:40:01 bes Exp $
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

=head1 NAME

link.pl - script for linking OTRS modules into framework root

=head1 SYNOPSIS

link.pl <source-module-folder> <otrs-folder>

link.pl <source-module-folder> <otrs-folder>

=head1 DESCRIPTION

This script installs a given OTRS module into the OTRS framework by creating
appropriate links.

Please send any questions, suggestions & complaints to <ot@otrs.com>

=cut

use strict;
use warnings;

my $Source = shift || die "Need Application CVS location as ARG0";
if (! -d $Source) {
    die "ERROR: invalid Application CVS directory '$Source'";
}
my $Dest = shift || die "Need Framework-Root location as ARG1";
if (! -d $Dest) {
    die "ERROR: invalid Framework-Root directory '$Dest'";
}

my @Dirs;
my $Start = $Source;
R($Start);

sub R {
    my $In = shift;
    my @List = glob("$In/*");
    foreach my $File (@List) {
        $File =~ s/\/\//\//g;
        # recurse into subdirectories
        if (-d $File) {
            # skip CVS directories
            if ($File !~ /\/CVS$/) {
                R($File);
            }
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
            # check directory of location (in case create a directory)
            if ("$Dest/$File" =~ /^(.*)\/(.+?|)$/)
            {
                my $Directory = $1;
                my @Directories = split(/\//, $Directory);
                my $DirectoryCurrent = '';
                foreach my $Directory (@Directories) {
                    $DirectoryCurrent .= "/$Directory";
                    if ($DirectoryCurrent && ! -d $DirectoryCurrent) {
                        if (mkdir $DirectoryCurrent) {
                            print STDERR "NOTICE: Create Directory $DirectoryCurrent\n";
                        }
                        else {
                            die "ERROR: can't create directory $DirectoryCurrent: $!";
                        }
                    }
                }
            }
            if (-l "$Dest/$File") {
                unlink ("$Dest/$File") || die "ERROR: Can't unlink symlink: $Dest/$File";
            }
            if (-e "$Dest/$File") {
                if (rename("$Dest/$File", "$Dest/$File.old")) {
                    print "NOTICE: Backup orig file: $Dest/$File.old\n";
                }
                else {
                    die "ERROR: Can't rename $Dest/$File to $Dest/$File.old: $!";
                }
            }
            if (!-e $Dest) {
                die "ERROR: No such directory: $Dest";
            }
            elsif (!-e $OrigFile) {
                die "ERROR: No such orig file: $OrigFile";
            }
            elsif (!symlink ($OrigFile, "$Dest/$File")) {
                die "ERROR: Can't $File link: $!";
            }
            else {
                print "NOTICE: Link: $OrigFile -> \n";
                print "NOTICE:       $Dest/$File\n";
            }
        }
    }
}
