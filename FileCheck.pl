#!/usr/bin/perl
# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use Getopt::Std;
use File::Find;
use XML::Simple;

=head1 NAME

FileCheck.pl - searchs for mistakes in the list of files registered in SOPM

=head1 SYNOPSIS

 FileCheck.pl -m <source-module-folder> [-v]

 [-v] optional to see intermediate results

=head1 DESCRIPTION

This script searchs for mistakes in the list of files registered
in SOPM file. It reads the complete sopm list and tries to find every file
in the main module directory or even look for all files in main module directory
and compare against the sopm list to see if you forgot to include some in the list.

=cut

# get options
my %Opt;
getopt( 'hm', \%Opt );

if ( exists $Opt{h} ) {
    Usage();
    exit;
}

# some globals
my $ModulePath;
my $CleanSOPMFile;

# look for module main directory in parameters and look for it.
if ( $Opt{m} && -d $Opt{m} ) {

    # find and read sopm in main path.
    $ModulePath = $Opt{m};
    $ModulePath =~ s{ /* \z}{}xms;

    my $SOPMFile = glob "$ModulePath/*.sopm";
    $CleanSOPMFile = $SOPMFile;
    $CleanSOPMFile =~ s{\Q$ModulePath\E/?}{}xms;

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
        Usage('sopm file not found');
    }

    exit;
}
elsif ( !$Opt{m} ) {
    Usage('needed module path!');
}
else {
    Usage('non existent path!');
}

sub GetPackageFileList {
    my %Param = @_;

    # look for needed parameters
    for my $Parameter (qw( SOPM )) {
        if ( !$Param{$Parameter} ) {
            die "\n Needed parameter, $Parameter! \n";
        }
    }

    my $SOPM = $Param{SOPM};

    die "\n can't find sopm file!: $SOPM \n" if !-e $SOPM;

    print "\n >> reading sopm file: $CleanSOPMFile ... \n";

    # build xml object
    my $XMLObject = XML::Simple->new(
        ForceArray => [qw(File)],
    );

    # read XML file
    my $XMLContent = $XMLObject->XMLin($SOPM);

    # find the list of needed files inside sopm.
    my @FileList = map { $_->{Location} } @{ $XMLContent->{Filelist}->{File} };

    if ( $Opt{v} ) {
        PrintFiles(
            Source      => 'SOPM file',
            ListOfFiles => \@FileList,
        );
    }

    return @FileList;
}

sub GetDirectoryFileList {
    my %Param = @_;

    # look for needed parameters
    for my $Needed (qw( ModuleDirectory )) {
        if ( !$Param{$Needed} ) {
            die "\n Needed parameter, $Needed! \n";
        }
    }

    # files and directories to ignore
    my @IgnoreFiles = qw(
        .cvsignore .project .includepath .*\.sopm \.tmp.* .filecheckignore
        .filecheckdirignore .gitignore
    );

    my @IgnoreDirs = qw( CVS .settings .git );

    my $Dir = $Param{ModuleDirectory};

    # set custom files to ignore file location
    my $CustomIgnoreFilesLocation = $Param{ModuleDirectory} . '/.filecheckignore';

    # set custom dirs to ignore file location
    my $CustomIgnoreDirsLocation = $Param{ModuleDirectory} . '/.filecheckdirignore';

    # read and add custom files to ignore
    if ( -e $CustomIgnoreFilesLocation ) {

        # check if file can not open
        my $FH;
        ## no critic
        if ( !open $FH, '<', $CustomIgnoreFilesLocation ) {
            ## use critic
            print "Can't open or read '$CustomIgnoreFilesLocation': $!"
        }
        else {
            my @CustomIgnoreFiles = <$FH>;
            for my $File (@CustomIgnoreFiles) {
                chomp($File);
                push @IgnoreFiles, $File;
            }
        }
    }

    # read and add custom files to ignore
    if ( -e $CustomIgnoreDirsLocation ) {

        # check if file can not open
        my $FH;
        ## no critic
        if ( !open $FH, '<', $CustomIgnoreDirsLocation ) {
            ## use critic
            print "Can't open or read '$CustomIgnoreDirsLocation': $!"
        }
        else {
            my @CustomIgnoreDirs = <$FH>;
            for my $Dir (@CustomIgnoreDirs) {
                chomp($Dir);
                push @IgnoreDirs, $Dir;
            }
        }
    }

    my @FileList;
    my $WantedFunction = sub {
        my $FullName  = $File::Find::name;
        my $Name      = $_;
        my $CleanName = $FullName;

        # cleaning FullName to store
        $CleanName =~ s{\A\Q$ModulePath\E/?}{};

        # filtering results
        # ignore directories
        return if -d $Name;

        # ignore files inside preconfigured directories
        my $MatchDir        = 0;
        my $MatchFile       = 0;
        my $MatchCustomFile = 0;

        IGNOREDIRECTORY:
        for my $IgnoreDirectory (@IgnoreDirs) {

            $MatchDir = $FullName =~ m{$IgnoreDirectory/}xms;

            last IGNOREDIRECTORY if $MatchDir;
        }

        IGNOREFILE:
        for my $IgnoreFile (@IgnoreFiles) {

            $MatchFile       = $Name =~ m{\A$IgnoreFile\z}xms;
            $MatchCustomFile = $CleanName =~ m{\A$IgnoreFile\z}xms;

            last IGNOREFILE if $MatchFile;
            last IGNOREFILE if $MatchCustomFile;
        }

        if ( !$MatchDir && !$MatchFile && !$MatchCustomFile ) {
            push @FileList, $CleanName;
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

        my @SortedFileList = sort @FileList;

        return @SortedFileList;
    }

    return 0;
}

sub PrintFiles {
    my %Param = @_;

    print "\n+ List of files in $Param{Source} +\n";
    print "---------\n";
    my $Counter = 0;
    for my $File ( sort @{ $Param{ListOfFiles} } ) {
        print "$File \n";
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
    for my $Needed (qw( SOPM Directory )) {
        if ( !$Param{$Needed} ) {
            die "\n Needed parameter, $Needed! \n";
        }
    }

    # convert array to hash to compare faster
    my %SOPM      = map { $_ => 1 } @{ $Param{SOPM} };
    my %Directory = map { $_ => 1 } @{ $Param{Directory} };

    # get files in SOPM and not in File System
    # diff Hashes
    my @SOPMvsDIR;
    for my $Key ( sort keys %SOPM ) {
        if ( !$Directory{$Key} ) {
            push @SOPMvsDIR, $Key;
        }
    }

    # get files in File System and not in SOPM
    # diff Hashes
    my @DIRvsSOPM;
    for my $Key ( sort keys %Directory ) {
        if ( !$SOPM{$Key} ) {
            push @DIRvsSOPM, $Key;
        }
    }

    if ( @DIRvsSOPM || @SOPMvsDIR ) {

        #Diff
        print "\n"
            . "\n"
            . "------------------------------------------------------\n"
            . "                    DIFF RESULTS    \n"
            . "------------------------------------------------------\n"
            . " SOPM:      $CleanSOPMFile \n"
            . " Directory: $ModulePath \n"
            . "------------------------------------------------------\n";

        # print diff
        if (@SOPMvsDIR) {
            print "----------------\n"
                . "This files are in SOPM but were not found in File System.\n"
                . "Please check for syntax errors\n"
                . "----------------\n";
            my $Counter = 0;
            for my $File ( sort @SOPMvsDIR ) {
                print "  " . $File . "\n";
                $Counter++;
            }
            print "----------------\n"
                . "Files: $Counter \n"
                . "----------------\n";
        }

        if (@DIRvsSOPM) {
            print "\n----------------\n"
                . "This files are in File System but were not found in SOPM.\n"
                . "Some times this is ok, but maybe you forgot to register them\n"
                . "in SOPM file\n"
                . "----------------\n";

            my $Counter = 0;
            for my $File ( sort @DIRvsSOPM ) {
                print "  $File\n";
                $Counter++;
            }
            print "----------------\n"
                . "Files: $Counter \n"
                . "----------------\n";
        }
    }
    else {
        print <<'END_OF_HERE';

----------------
Good Job, all files are well registered!
----------------

END_OF_HERE
    }
}

# exit after printing the usage message
sub Usage {
    my ($Message) = @_;

    $Message ||= '';

    print <<"END_OF_HERE";

$Message

USAGE:
   FileCheck.pl -m <source-module-path> -v (optional to see intermediate results)

    You can add custom files to ignore in source-module-path/.filecheckignore
        .filecheckignore content Example:

            doc/en/ModuleDoc.xml
            Changes.MyModule

    You can add custom directories to ignore in source-module-path/.filecheckdirignore
        .filecheckdirignore content Example:

            development
            testing

END_OF_HERE

    exit 1;
}

1;
