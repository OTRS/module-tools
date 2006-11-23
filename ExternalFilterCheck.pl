#!/usr/bin/perl -w
# --
# ExternalFilterCheck.pl - a tool to check all files with filter.pl of the cvs
# Copyright (C) 2001-2006 OTRS GmbH, http://otrs.org/
# --
# $Id: ExternalFilterCheck.pl,v 1.1 2006-11-23 08:49:04 tr Exp $
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

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin)."/Kernel/cpan-lib";

use strict;

use vars qw($VERSION $RealBin);
$VERSION = '$Revision: 1.1 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

use Getopt::Std;

# get options
my %Opts = ();
my $Filterpath = '';
my $CheckDirectory = '';

getopt('hfdewn', \%Opts);
if ($Opts{'h'} || !$Opts{'f'} || !$Opts{'d'}) {
    print "ExternalFilterCheck.pl <Revision $VERSION> - OTRS check all files with filter.pl\n";
    print "Copyright (c) 2001-2006 OTRS GmbH, http://otrs.org/\n";
    print "usage: ExternalFilterCheck.pl -f /path/to/filter.pl -d /path/to/wanteddirectory\n";
    print "           -e 'yes' shows errors -w 'yes' shows warnings -n 'yes' shows notice\n";
    exit 1;
}

if ($Opts{'f'}) {
    $Filterpath = $Opts{'f'};
}
if ($Opts{'d'}) {
    $CheckDirectory = $Opts{'d'};
}

my $Bugfiles = ReadDirectory($Filterpath, $CheckDirectory);
print "\n";

# the whitelist is for a better testing
# so you can ignore some files
my %WhiteList = ();
#$WhiteList{'Advisory.pm'} = 1;
$WhiteList{'ZZZAuto.pm'}  = 1;
$WhiteList{'ZZZAAuto.pm'} = 1;
foreach my $Filename (keys %{$Bugfiles}) {
    $Filename =~ /\/([^\/]+)$/;
    if ($Bugfiles->{$Filename} && !$WhiteList{$1}) {
        if (defined($Opts{'n'}) && $Bugfiles->{$Filename}{Notice}) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Notice} . "\n";
        }
        if (defined($Opts{'w'}) && $Bugfiles->{$Filename}{Warning}) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Warning} . "\n";
        }
        if (defined($Opts{'e'}) && $Bugfiles->{$Filename}{Error}) {
            print $Filename . " -> \n" . $Bugfiles->{$Filename}{Error} . "\n";
        }
        if ($Bugfiles->{$Filename}{Misc}) {
            print $Filename . " MISC -> \n" . $Bugfiles->{$Filename}{Misc} . "\n";
        }
    }
}

1;

sub ReadDirectory {
    my $Filterpath = shift;
    my $CheckDirectory = shift;
    my @Directory = ();
    my @File = ();
    my @Symlink = ();
    my $Bugfiles = {};

    if (!opendir(DIR, $CheckDirectory)) {
        print "Can not open Directory: $CheckDirectory";
        return;
    }

    while (defined (my $Filename = readdir DIR)) {
        if (-d "$CheckDirectory/$Filename") {
            if ($Filename ne 'CVS' && $Filename ne '..' && $Filename ne '.') {
                push(@Directory, "$CheckDirectory/$Filename")
            }
        }
        elsif (-l "$CheckDirectory/$Filename"){
            push (@Symlink,"$CheckDirectory/$Filename");
        }
        elsif (-f "$CheckDirectory/$Filename"){
            unless ($Filename=~ /.*\.kdevses$/ || $Filename=~ /.*\.kdevelop$/|| $Filename=~ /.*\.tmp$/) {
                push(@File, "$CheckDirectory/$Filename")
            }
        }
    }
    closedir(DIR);

    foreach $_ (@Symlink) {
        print "Symlink : $_ \n";
    }

    foreach my $Directoryname (@Directory) {
        %{$Bugfiles} = (%{$Bugfiles}, %{ReadDirectory($Filterpath, $Directoryname)});
        #print "Directory : $Directoryname \n";
    }

    my %Bugfiles =();
    foreach my $Filenames (@File) {
        system ("cp $Filenames $Filenames.ttmp");

        if (open (OUTPUT, "perl $Filterpath/filter-extended.pl $CheckDirectory $Filenames |")) {
            while (<OUTPUT>) {
                if ($_=~ /^ERROR:.+/) {
                    $Bugfiles->{$Filenames}{Error} .= $_;
                }
                elsif ($_=~ /^NOTICE/) {
                    $Bugfiles->{$Filenames}{Notice} .= $_;
                }
                elsif ($_=~ /^WARNING/) {
                    $Bugfiles->{$Filenames}{Warning} .= $_;
                }
                elsif ($_ && $_ ne "\n" && !$_=~ /^ERROR/) {
                    $Bugfiles->{$Filenames}{Misc} .= $_;
                }
            }
            close (OUTPUT);
        }

        if (-f "$Filenames.tmp") {
            system ("rm $Filenames.tmp");
        }
        system ("rm $Filenames");
        system ("mv $Filenames.ttmp $Filenames");
    }

    return $Bugfiles;
}

1;
