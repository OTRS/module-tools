#!/usr/bin/perl
# --
# remove_links.pl - script to remove links from an OTRS framework
# Copyright (C) 2001-2013 OTRS AG, http://otrs.com/
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

my $Dest = shift || die "Need Application-Root location as ARG1";
if ( !-d $Dest ) {
    die "ERROR: invalid Application-Root directory '$Dest'";
}

if ( !( -e $Dest . '/Kernel' && -e $Dest . '/Kernel/System' ) ) {
    print <<"WARNING";
Can't find $Dest/Kernel and $Dest/Kernel/System, so I assume it's not a
root directory of an OTRS instance. Remove links anyway? [y/N]
WARNING

    chomp( my $Answer = <STDIN> );

    if ( $Answer !~ m{ ^ y $ }xi ) {
        exit 1;
    }
}

my @Dirs  = ();
my $Start = $Dest;
Remove($Start);

sub Remove {
    my $In   = shift;
    my @List = glob("$In/*");

    for my $File (@List) {

        $File =~ s/\/\//\//g;

        if ( -d $File ) {
            Remove($File);
        }
        else {

            my $OrigFile = $File;
            $File =~ s/$Start//;

            if ( -l $OrigFile ) {

                print "Unlink Symlink: $File\n";
                unlink $OrigFile || die $!;

                if ( -f "$OrigFile.old" ) {
                    print "Restore orginal copy: $File\n";
                    rename( "$OrigFile.old", $OrigFile ) || die $!;
                }
            }
        }
    }
}

exit 0;
