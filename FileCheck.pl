#!/usr/bin/perl -w
# --
# module-tools/FileCheck.pl - searchs for existent mistakes in the list of files registered in SOPM
# Copyright (C) 2001-2010 OTRS AG, http://otrs.org/
# --
# $Id: FileCheck.pl,v 1.1 2010-08-24 19:38:56 dz Exp $
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
# or see L<http://www.gnu.org/licenses/agpl.txt>.
# --

use strict;
use warnings;

use Getopt::Std;
use File::Find;
use XML::Simple;
use Data::Dumper;

=head1 NAME

FileCheck.pl - searchs for existent mistakes in the list of files registered in SOPM

=head1 SYNOPSIS

 FileCheck.pl <source-module-folder> [-v]

 [-v] optional to see intermidiate results

=head1 DESCRIPTION

This module searchs for existent mistakes in the list of files registered
in SOPM file, this can reads the complete sopm list and try to find every file
in the main module directory or even look for all files in main module directory
and compare against the sopm list to see if you forgot include some in the list.

=head1 TODO

=cut

# get options
my (%Opt);

getopt( 'hm', \%Opt );

if ( $Opt{h} ) {
    &Usage;
    exit;
}

my $ModulePath;
my $SOPMFile;
my %ListOfFiles;

# look for module main directory in parameters and look for it.
if ( $Opt{m} && -d $Opt{m} ) {

    # find and read sopm in main path.
    $ModulePath = $Opt{m};
    $ModulePath =~ s{(\w*)(\/)*}{$1}xms;

    $SOPMFile = glob "$ModulePath/*.sopm";

    if ($SOPMFile) {

        # get list of files from SOPM file.
        my @SOPM = GetPackageFileList( SOPM => $SOPMFile );

        # look in path for every file in module directory.
        my @Directory = GetDirectoryFileList( ModuleDirectory => $ModulePath );

        # list all files found and those which not.
        DiffList(
            SOPM      => \@SOPM,
            Directory => \@Directory,
        );
    }
    else {
        Usage("sopm file doesn't found");
    }

    exit;
}
elsif ( !$Opt{m} ) {
    Usage("needed module path!");
}
else {
    &Usage("non existent path!");
}

sub GetPackageFileList {
    my %Param = @_;
    my $SOPM;
    my @FileList;

    # look for needed parameters
    for my $Parameter (qw( SOPM )) {
        if ( !$Param{$Parameter} ) {
            die "\n Needed parameter, $Parameter! \n";
        }
    }

    $SOPM = $Param{SOPM};

    if ( -e $SOPM ) {
        print "\n >> reading sopm file: $SOPM ... \n";

        # build xml object
        my $XMLObject = new XML::Simple;

        # read XML file
        my $XMLContent = $XMLObject->XMLin("$SOPM");

        # find the list of needed files inside sopm.
        for my $File ( @{ $XMLContent->{Filelist}->{File} } ) {
            push @FileList, $File->{Location};
        }

        if (@FileList) {
            if ( $Opt{v} ) {
                PrintFiles(
                    Source      => 'SOPM file',
                    ListOfFiles => \@FileList,
                );
            }
            return @FileList;
        }
        else {
            return 0;
        }
    }
    else {
        die "\n can't find sopm file!: $SOPM \n"
    }
}

sub GetDirectoryFileList {
    my %Param = @_;
    my $Dir;
    my @FileList;

    # look for needed parameters
    for my $Parameter (qw( ModuleDirectory )) {
        if ( !$Param{$Parameter} ) {
            die "\n Needed parameter, $Parameter! \n";
        }
    }

    # files and directories to ignore
    my @IgnoreFiles = ( '.cvsignore', '.project', '.*\.sopm', '\.tmp.*', );
    my @IgnoreDirs = ( 'CVS', '.settings', );

    $Dir = $Param{ModuleDirectory};

    my $WantedFunction =
        sub {
        my $Directory = $File::Find::dir;
        my $FullName  = $File::Find::name;
        my $Name      = $_;

        # filtering results
        $Directory =~ s{\A$Dir/(.*)?}{$1};
        $FullName  =~ s{\A$Dir/(.*)?}{$1};

        # ignore directories
        if ( -d $Name ) {
            return;
        }
        else {

            # ignore files inside preconfigured directories
            my $MatchD = 0;
            my $MatchF = 0;

            for my $IgnoreDirectory (@IgnoreDirs) {
                $MatchD = $FullName =~ m{$IgnoreDirectory/}xms;
                last if ($MatchD);
            }

            for my $IgnoreFile (@IgnoreFiles) {
                $MatchF = $Name =~ m{\A$IgnoreFile\z}xms;
                last if ($MatchF);
            }

            if ( !$MatchD && !$MatchF ) {
                push @FileList, $FullName;
            }
        }
        };

    print " >> reading file system: $Dir ... \n";
    find( $WantedFunction, $Dir );

    if (@FileList) {
        if ( $Opt{v} ) {
            PrintFiles(
                Source      => 'file system',
                ListOfFiles => \@FileList,
            );
        }
        return @FileList;
    }
    else {
        return 0;
    }
}

sub PrintFiles() {
    my %Param = @_;

    print "\n"
        . "+ List of files in $Param{Source} +\n";
    print "---------\n";
    my $Counter = 0;
    for my $file ( @{ $Param{ListOfFiles} } ) {
        print "$file \n";
        $Counter++;
    }
    print "---------\n"
        . "Count: $Counter \n"
        . "---------\n"
        . "\n";
}

sub DiffList {
    my %Param = @_;

    # look for needed parameters
    for my $Parameter (qw( SOPM Directory )) {
        if ( !$Param{$Parameter} ) {
            die "\n Needed parameter, $Parameter! \n";
        }
    }

    # convert array to hash to compare faster
    my %SOPM;
    my %Directory = @{ $Param{Directory} };

    for my $Key ( @{ $Param{SOPM} } ) {
        $SOPM{$Key} = 1;
    }

    for my $Key ( @{ $Param{Directory} } ) {
        $Directory{$Key} = 1;
    }

    # get files in SOPM and not in File System
    # diff Hashes
    my @SOPMvsDIR;
    for my $key ( keys %SOPM ) {
        if ( !$Directory{$key} ) {
            push @SOPMvsDIR, $key;
        }
    }

    # get files in File System and not in SOPM
    # diff Hashes
    my @DIRvsSOPM;
    for my $key ( keys %Directory ) {
        if ( !$SOPM{$key} ) {
            push @DIRvsSOPM, $key;
        }
    }

    if ( @DIRvsSOPM || @SOPMvsDIR ) {

        #Diff
        print "\n\n"
            . "------------------------------------------------------\n"
            . "    DIFF RESULTS Comparing $SOPMFile & $ModulePath  \n"
            . "------------------------------------------------------\n";

        # print diff
        if (@SOPMvsDIR) {
            print "----------------\n"
                . "This files are in SOPM but were not found in File System\n"
                . "Please check for syntax errors\n"
                . "----------------\n";
            my $Counter = 0;
            for my $file (@SOPMvsDIR) {
                print "  " . $file . "\n";
                $Counter++;
            }
            print "----------------\n"
                . "Files: $Counter \n"
                . "----------------\n";
        }

        if (@DIRvsSOPM) {
            print "\n----------------\n"
                . "This files are in File System but were not found in SOPM\n"
                . "Some times this is ok, but may be you miss write this files\n"
                . "in SOPM file\n"
                . "--------\n";

            my $Counter = 0;
            for my $file (@DIRvsSOPM) {
                print "  " . $file . "\n";
                $Counter++;
            }
            print "----------------\n"
                . "Files: $Counter \n"
                . "----------------\n";
        }
    }
    else {
        print "\n----------------\n"
            . "Good Job, all files are well registered!! :)\n"
            . "----------------\n";

    }
}

sub Usage {
    my ($Message) = @_;
    print "Usage";
    print STDERR <<"End-of-Here";

$Message

USAGE:
    FileCheck.pl -m <source-module-path> -v (optional to see intermidiate results)

End-of-Here

    return;
}
1;
