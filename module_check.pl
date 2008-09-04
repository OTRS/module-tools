#!/usr/bin/perl -w
# --
# module-tools/module_check.pl - script to check OTRS modules
# Copyright (C) 2001-2008 OTRS AG, http://otrs.org/
# --
# $Id: module_check.pl,v 1.6 2008-09-04 12:21:29 mh Exp $
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

use Getopt::Std;
use File::Find;

use File::Temp qw( tempfile );

use vars qw($VERSION);
$VERSION = qw($Revision: 1.6 $) [1];

# get options
my %Opts = ();
getopt('omd', \%Opts);

# set default
if (!$Opts{'o'} || !$Opts{'m'} ) {
    $Opts{'h'} = 1;
}
if ( $Opts{'h'} ) {
    print "module_check.pl <Revision $VERSION> - Check OTRS modules\n";
    print "Copyright (C) 2001-2008 OTRS AG, http://otrs.org/\n";
    print "usage: module_check.pl -o <Original-Framework-Path> -m <Module-Path> -v [verbose mode] -d [debug mode 1]\n\n";
    exit 1;
}

my $OriginalPath = $Opts{'o'} . '/';
my $ModulePath   = $Opts{'m'} . '/';

$OriginalPath =~ s{ /+ $ }{/}xms;
$ModulePath =~ s{ /+ $ }{/}xms;

print "\n";
print "Original-Framework-Path: [$OriginalPath]\n";
print "Module-Path            : [$ModulePath]\n\n";
print "-----------------------------------------------------------------------------------------------------\n";

find( \&CheckFile, ($ModulePath) );

1;

sub CheckFile {

    # get current module filename and directory from File::Find
    my $ModuleFile = $File::Find::name;
    my $ModuleDir  = $File::Find::dir;

    # skip directories
    return if -d $ModuleFile;

    # skip file if not of file type (.pl .pm .dtl)
    return if $ModuleFile !~ m{ [.](pl|pm|dtl|t) \s* \z }ixms;

    # get original file name from OldId
    my $OriginalFilename = OriginalFilenameGet(File => $ModuleFile);
    return if !$OriginalFilename;

    # get and prepare module content
    my $ModuleContent = ModuleContentPrepare(File => $ModuleFile );

    # build original filename
    my $OriginalFile = $ModuleDir . '/';
    $OriginalFile =~ s{ $ModulePath }{$OriginalPath}xms;
    $OriginalFile .= $OriginalFilename;

    # get and prepare original content
    my $OriginalContent = OriginalContentPrepare(File => $OriginalFile );

    # crate temp files for the diff
    my $ModuleFH   = File::Temp->new( DIR => '/tmp' );
    my $OriginalFH = File::Temp->new( DIR => '/tmp');

    # get temp file names
    my $ModuleTempfile   = $ModuleFH->filename;
    my $OriginalTempfile = $OriginalFH->filename;

    # save content to temp files
    print $ModuleFH $ModuleContent;
    print $OriginalFH $OriginalContent;

    # make a diff of the content
    my $DiffResult = `diff $OriginalTempfile $ModuleTempfile`;

    # print diff result
    if ( $Opts{'v'} || $DiffResult ) {
        print "DIFF RESULT for:\n";
        print "$OriginalFile\n";
        print "$ModuleFile\n\n";
        print $DiffResult . "\n\n" if $DiffResult;
    }

    # verify the real files in debug mode
    if ( $Opts{'d'} ) {
        $DiffResult = `diff $OriginalFile $ModuleFile`;
        print "-----------------------------------------------------------------------------------------------------\n";
        print "VERIFY DIFF\n";
        print $DiffResult . "\n\n";
    }

    if ( $Opts{'v'} || $DiffResult ) {
        print "-----------------------------------------------------------------------------------------------------\n";
    }

    return 1;
}

sub OriginalContentPrepare {
    my (%Param) = @_;

    # open file and get content
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    my $Content = do { local $/; <$FH> };
    close $FH;

    # clean the content
    $Content = ContentClean( Content => $Content );

    return $Content;
}

sub ModuleContentPrepare {
    my (%Param) = @_;

    # open file and get content
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    my $Content = do { local $/; <$FH> };
    close $FH;

    my @NewCodeBlocks;
    while ( $Content =~ s{
        ^ \# [ ] --- \s*? $ \s
        ^ \# [ ] .+? \s*? $ \s
        ^ \# [ ] --- \s*? $ \s
        (.+?)
        ^ \# [ ] --- \s*? $
    }{---PLACEHOLDER---}xms
    ) {
        my $Block = $1;
        my $NewCode = '';
        my @Lines = split q{\n}, $Block;
        LINE:
        for my $Line ( @Lines ) {
            if ( $Line =~ s{ ^ \# (.*?) $ }{}xms ) {
                $NewCode .= $1 . "\n";
            }
            else {
                last LINE;
            }
        }
        push @NewCodeBlocks, $NewCode;

    }

    while ( $Content =~ s{ ^ ---PLACEHOLDER--- $ \s }{ shift @NewCodeBlocks }xmse ) {

        # Do nothing  *lol*
    }

    # delete ID line
    $Content =~ s{ ^ \# [ ] \$[I]d: .+? $ }{}ixms;

    # replace OldId with Id
    $Content =~ s{ \s ^ \# [ ] \$OldId: }{\# \$Id:}ixms;

    # clean the content
    $Content = ContentClean( Content => $Content );

    return $Content;
}

sub OriginalFilenameGet {
    my (%Param) = @_;

    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";

    my $Counter = 0;
    my $Filename;
    LINE:
    while (my $Line = <$FH>) {

        # Example:
        # $OldId: AgentTicketNote.pm,v 1.34.2.4 2008/03/25 13:27:05 ub Exp $
        if ( $Line =~ m{ \A \# [ ] \$OldId: [ ] (.+?) ,v [ ] }ixms ) {
            $Filename = $1;
            last LINE;
        }
    }
    continue {
        $Counter++;
        last LINE if $Counter > 50;
    }
    close $FH;

    return $Filename;
}

sub ContentClean {
    my (%Param) = @_;

    my $Content = $Param{Content};

    # delete the different version lines

    # example1: $VERSION = qw($Revision: 1.6 $) [1];
    $Content =~ s{ ^ \$VERSION [ ] = [ ] qw \( \$[R]evision: [ ] .+? $ }{}ixms;

    # example2: $VERSION = '$Revision: 1.6 $';
    $Content =~ s{ ^ \$VERSION [ ] = [ ] '     \$[R]evision: [ ] .+? $ }{}ixms;

    # example3:
    #=head1 VERSION
    #
    #$Revision: 1.6 $ $Date: 2008-09-04 12:21:29 $
    #
    #=cut
    $Content =~ s{
        ^ =head1 [ ] VERSION    $ \s
        ^                       $ \s
        ^ \$[R]evision: [ ] .+? $ \s
        ^                       $ \s
        ^ =cut                  $
    }{}ixms;

    # delete copyright line
    $Content =~ s{ ^ \# [ ] Copyright [ ] \( C \) .+?  http://otrs\.(org|com)/ $ }{}ixms;

    # delete GPL line
    $Content =~ s{
        ^ \# [ ] did [ ] not [ ] receive [ ] this [ ] file, [ ] see [ ] http://www\.gnu\.org .+? $
    }{}ixms;

    return $Content;
}

exit 0;
