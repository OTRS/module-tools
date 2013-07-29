#!/usr/bin/perl
# --
# ExternalFilterCheck.pl - a tool to check all files with filter.pl of the cvs
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
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

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . "/Kernel/cpan-lib";

use strict;
use warnings;

use vars qw($RealBin);

use Getopt::Std;

# get options
my %Opts           = ();
my $Filterpath     = '';
my $CheckDirectory = '';

getopt( 'hfdn', \%Opts );
if ( $Opts{h} || !$Opts{f} || !$Opts{d} ) {
    print "ExternalFilterCheck.pl - OTRS check all files with filter.pl\n";
    print "Copyright (C) 2001-2012 OTRS AG, http://otrs.org/\n";
    print "usage: ExternalFilterCheck.pl -f /path/to/filter.pl -d /path/to/wanteddirectory -ew\n";
    print "       -e -> show errors\n";
    print "       -w -> show warrnings\n";
    print "       -m -> modify code\n";
    exit 1;
}

if ( $Opts{f} ) {
    $Filterpath = $Opts{f};
}
if ( $Opts{d} ) {
    $CheckDirectory = $Opts{d};
}

my $Modify = defined $Opts{m} ? 1 : 0;

my $Bugfiles = ReadDirectory( $Filterpath, $CheckDirectory, $Modify );
print "\n";

# the whitelist is for a better testing
# so you can ignore some files
my %WhiteList = ();

#$WhiteList{'Advisory.pm'} = 1;
$WhiteList{'ZZZAuto.pm'}  = 1;
$WhiteList{'ZZZAAuto.pm'} = 1;
for my $Filename ( keys %{$Bugfiles} ) {
    $Filename =~ /\/([^\/]+)$/;
    if ( $Bugfiles->{$Filename} && !$WhiteList{$1} ) {
        if ( defined( $Opts{n} ) && $Bugfiles->{$Filename}{Notice} ) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Notice} . "\n";
        }
        if ( defined( $Opts{w} ) && $Bugfiles->{$Filename}{Warning} ) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Warning} . "\n";
        }
        if ( defined( $Opts{e} ) && $Bugfiles->{$Filename}{Error} ) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Error} . "\n";
        }
        if ( $Bugfiles->{$Filename}{Misc} ) {
            print $Filename . " MISC -> \n" . $Bugfiles->{$Filename}{Misc} . "\n";
        }
    }
}

1;

sub ReadDirectory {
    my $Filterpath     = shift;
    my $CheckDirectory = shift;
    my $Modify         = shift;
    my @Directory      = ();
    my @File           = ();
    my @Symlink        = ();
    my $Bugfiles       = {};

    if ( !opendir DIR, $CheckDirectory ) {
        print "Can not open Directory: $CheckDirectory";
        return;
    }

    while ( defined( my $Filename = readdir DIR ) ) {
        if ( -d "$CheckDirectory/$Filename" ) {
            if ( $Filename ne 'CVS' && $Filename ne '..' && $Filename ne '.' && $Filename ne 'var' )
            {
                push @Directory, "$CheckDirectory/$Filename";
            }
        }
        elsif ( -l "$CheckDirectory/$Filename" ) {
            push @Symlink, "$CheckDirectory/$Filename";
        }
        elsif ( -f "$CheckDirectory/$Filename" ) {
            unless (
                $Filename    =~ /.*\.kdevses$/
                || $Filename =~ /.*\.kdevelop$/
                || $Filename =~ /.*\.tmp$/
                )
            {
                push @File, "$CheckDirectory/$Filename";
            }
        }
    }
    closedir DIR;

    for (@Symlink) {
        print "Symlink : $_ \n";
    }

    for my $Directoryname (@Directory) {
        %{$Bugfiles} = ( %{$Bugfiles}, %{ ReadDirectory( $Filterpath, $Directoryname ) } );

        #print "Directory : $Directoryname \n";
    }

    my %Bugfiles = ();
    for my $Filenames (@File) {
        next if $Filenames =~ m{\.cvsignore}xms;
        system "cp $Filenames $Filenames.ttmp";

        # if (open (OUTPUT, "perl $Filterpath/filter.pl $CheckDirectory $Filenames |")) {
        if ( open OUTPUT, "perl $Filterpath/filter-extended.pl $CheckDirectory $Filenames |" ) {
            while (<OUTPUT>) {
                if ( $_ =~ /^ERROR:.+/ ) {
                    $Bugfiles->{$Filenames}{Error} .= $_;
                }
                elsif ( $_ =~ /^NOTICE/ ) {
                    $Bugfiles->{$Filenames}{Notice} .= $_;
                }
                elsif ( $_ =~ /^WARNING/ ) {
                    $Bugfiles->{$Filenames}{Warning} .= $_;
                }
                elsif ( $_ && $_ ne "\n" && !$_ =~ /^ERROR/ ) {
                    $Bugfiles->{$Filenames}{Misc} .= $_;
                }
            }
            close OUTPUT;
        }

        if ( -f "$Filenames.tmp" ) {
            system "rm $Filenames.tmp";
        }

        if ( !$Modify ) {
            system "rm $Filenames";
            system "mv $Filenames.ttmp $Filenames";
        }
        else {
            system "rm $Filenames.ttmp";
        }
    }

    return $Bugfiles;
}

1;
