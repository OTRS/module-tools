#!/usr/bin/perl
# --
# module_check.pl - script to check OTRS modules
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

=head1 NAME

module_check.pl - script to check OTRS modules

=head1 SYNOPSIS

module_check.pl -o <Original-Framework-Path> -m <Module-Path> -v [verbose mode] -d [debug mode 1] [diff options: -u|-b|-B|-w]

=head1 DESCRIPTION

Check the change markers for the files that contain an OldID.

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;

use Getopt::Std;
use File::Find;

use File::Temp qw( tempfile );

# get options
my %Opts = ();
getopt('omd', \%Opts);

# set default
if (!$Opts{'o'} || !$Opts{'m'} ) {
    $Opts{'h'} = 1;
}
if ( $Opts{'h'} ) {
    print "\nmodule_check.pl - Check OTRS modules\n";
    print "Copyright (C) 2001-2013 OTRS AG, http://otrs.com/\n\n";
    print "usage:\n   module_check.pl -o <Original-Framework-Path> -m <Module-Path> -v [verbose mode] -d [debug mode 1] [diff options: -u|-b|-B|-w]\n\n";
    print "example:\n   /workspace/module-tools/module_check.pl -o /workspace/otrs-git/ -m /workspace/ITSMCore_3_3/\n\n";
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

=item CheckFile

No documentation yet.

=cut

sub CheckFile {

    # get current module filename and directory from File::Find
    my $ModuleFile = $File::Find::name;
    my $ModuleDir  = $File::Find::dir;

    # skip directories
    return if -d $ModuleFile;

    # skip CVS directories
    return if $ModuleDir =~ m{ /CVS|\.git /? }xms;

    # check only Perl- and Template-files
    return if $ModuleFile !~ m{ [.](pl|pm|dtl|t) \s* \z }ixms;

    # get original file name from OldId, continue only when an original name was found
    my $OriginalFilename = OriginalFilenameGet(File => $ModuleFile);
    return if !$OriginalFilename;

    # get and prepare module content
    my $ModuleContent = ModuleContentPrepare(File => $ModuleFile );

    # build original filename
    my $OriginalFile = $ModuleDir . '/';

    $OriginalFile =~ s{ $ModulePath }{$OriginalPath}xms;
    $OriginalFile =~ s{ /Kernel/Custom/ }{/}xms;
    $OriginalFile =~ s{ /Custom/ }{/}xms;
    $OriginalFile .= $OriginalFilename;
    $OriginalFile  =~ s{\s}{}xms;

    # get and prepare original content
    my $OriginalContent = OriginalContentPrepare(File => $OriginalFile );

    # crate temp files for the diff
    my $ModuleFH   = File::Temp->new( DIR => '/tmp' );
    my $OriginalFH = File::Temp->new( DIR => '/tmp');

    # get temp file names
    my $ModuleTempfile   = $ModuleFH->filename();
    my $OriginalTempfile = $OriginalFH->filename();

    # save content to temp files
    print $ModuleFH $ModuleContent;
    print $OriginalFH $OriginalContent;

    # process diff options
    my $DiffOptions = '';
    for my $Opt ( qw(u b B w) ) {
        if ( defined( $Opts{$Opt} ) ) {
            $DiffOptions .= " -$Opt";
        }
    }

    # make a diff of the content
    my $DiffResult = `diff $DiffOptions $OriginalTempfile $ModuleTempfile`;

    # print diff result
    if ( $Opts{'v'} || $DiffResult ) {
        print "DIFF RESULT for:\n";
        print "$OriginalFile\n";
        print "$ModuleFile\n\n";
        print $DiffResult . "\n\n" if $DiffResult;
    }

    # verify the real files in debug mode
    if ( $Opts{'d'} ) {
        $DiffResult = `diff $DiffOptions $OriginalFile $ModuleFile`;
        print "-----------------------------------------------------------------------------------------------------\n";
        print "VERIFY DIFF\n";
        print $DiffResult . "\n\n";
    }

    if ( $Opts{'v'} || $DiffResult ) {
        print "-----------------------------------------------------------------------------------------------------\n";
    }

    return 1;
}

=item OriginalContentPrepare

No documentation yet.

=cut

sub OriginalContentPrepare {
    my (%Param) = @_;

    # open file and get content
    ## no critic
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    ## use critic
    my $Content = do { local $/; <$FH> };
    close $FH;

    # clean the content
    $Content = ContentClean( Content => $Content );

    return $Content;
}

=item ModuleContentPrepare

No documentation yet.

=cut

sub ModuleContentPrepare {
    my (%Param) = @_;

    # open file and get content
    ## no critic
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    ## use critic
    my $Content = do { local $/; <$FH> };
    close $FH;

    # prevent checking of files with nested markers (markers within markers)
    if ( $Content =~ m{
        (
            ^ \# [ ] --- [ \t]* \n
            ^ \# [ ] [^\n ][^\n]+ \n
            ^ \# [ ] --- [ \t]* \n
            (?: (?! ^ \# [ ] --- [ \t]* \n ). )+
            ^ \# [ ] --- [ \t]* \n
            ^ \# [ ] [^\n ][^\n]+ \n
            ^ \# [ ] --- [ \t]* \n
        )
    }xms ) {
        die "Nested custom markers found in '$Param{File}': $1!";
    }

    my @NewCodeBlocks;
    while ( $Content =~ s{
        ^ [ \t]* \# [ ] --- [ \t]* \n
        ^ [ \t]* \# [ ] [^\n]+ \n
        ^ [ \t]* \# [ ] --- [ \t]* \n
        ( .+? )
        ^ [ \t]* \# [ ] --- [ \t]* \n
    }{---PLACEHOLDER---\n}xms
    ) {
        my $Block = $1;
        my $NewCode = '';
        my @Lines = split q{\n}, $Block;
        LINE:
        for my $Line ( @Lines ) {
            # this extra match is necessary because filter.pl will not allow
            # lines beginning with "##" but which are necessary to cover the case
            # of removed lines that begin as a comment ("#").  very special case,
            # it catches lines beginning with # ' ' #.
            if ( $Line =~ s{ \A \# [ ] ( \# .* ) \z }{}xms ) {
                $NewCode .= $1 . "\n";
            }
            elsif ( $Line =~ s{ \A \# ( .* ) \z }{}xms ) {
                $NewCode .= $1 . "\n";
            }
            else {
                last LINE;
            }
        }
        push @NewCodeBlocks, $NewCode;

    }

    # put formerly commented code in place
    $Content =~ s{ ^ ---PLACEHOLDER--- $ \s }{ shift @NewCodeBlocks }xmseg;

    # delete $origin line
    # Example:
    # $origin: https://github.com/OTRS/otrs/blob/c9a71af026e3407b6866e49b0c68346e28b19da8/Kernel/Modules/AgentTicketPhone.pm
    $Content =~ s{ ^ \# [ ] ( \$origin: [^\n]+ ) \n ( ^ \# [ ] -- \n )? }{}xms;

    # clean the content
    $Content = ContentClean( Content => $Content );

    return $Content;
}

=item OriginalFilenameGet

No documentation yet.

=cut

sub OriginalFilenameGet {
    my (%Param) = @_;

    ## no critic
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    ## use critic

    my $Counter = 0;
    my $Filename;
    LINE:
    while (my $Line = <$FH>) {

        # Example:
        # $OldId: AgentTicketNote.pm,v 1.34.2.4 2008/03/25 13:27:05 ub Exp $
        # or:
        # $origin: https://github.com/OTRS/otrs/blob/c9a71af026e3407b6866e49b0c68346e28b19da8/Kernel/Modules/AgentTicketPhone.pm
        if ( $Line =~ m{ \A \# [ ] \$OldId: [ ] (.+?) ,v [ ] }ixms || $Line =~ m{ \A \# [ ] \$origin: [ ] \S+ / ([^/]+) }ixms ) {

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

=item ContentClean

No documentation yet.

=cut

sub ContentClean {
    my (%Param) = @_;

    my $Content = $Param{Content};

    # delete the different version lines

    # example1: $VERSION = qw($Revision: 1.30 $) [1];
    $Content =~ s{ ^ \$VERSION [ ] = [ ] qw \( \$[R]evision: [ ] .+? $ \n }{}ixms;

    # example2: $VERSION = '$Revision: 1.30 $';
    $Content =~ s{ ^ \$VERSION [ ] = [ ] '     \$[R]evision: [ ] .+? $ \n }{}ixms;


    # example3:
    #=head1 VERSION
    #
    #$Revision: 1.30 $ $Date: 2012/11/22 13:35:47 $
    #
    #=cut
    $Content =~ s{
        ^ =head1 [ ] VERSION    $ \s
        ^                       $ \s
        ^ \$[R]evision: [ ] .+? $ \s
        ^                       $ \s
        ^ =cut                  $
    }{}ixms;

    # delete the 'use vars qw($VERSION);' line
    $Content =~ s{ ( ^ $ \n )?  ^ use [ ] vars [ ] qw\(\$VERSION\); $ \n }{}ixms;

    # delete the $Id, $OldId, $OldId2 lines, followed by an optional divider comment line
    $Content =~ s{ ^ \# [ ] \$(Old)?Id(2)?: .+? \$ $ \n ( ^ \# [ ] -- $ \n )? }{}gixms;

    # delete copyright line
    $Content =~ s{ ^ \# [ ] Copyright [ ] \( C \) .+?  http://otrs\.(org|com)/ $ }{}ixms;

    # delete copyright line in help output of scripts
    $Content =~ s{ ^ [ ]* print [ ] "Copyright [ ] \( C \) .+?  http://otrs\.(org|com)/\\n"; $ }{}ixms;

    # delete GPL line
    $Content =~ s{
        ^ \# [ ] did [ ] not [ ] receive [ ] this [ ] file, [ ] see [ ] http://www\.gnu\.org .+? $
    }{}ixms;

    # Delete the standard comment with the filenname and an optional description.
    # The name of the file could have changed.
    # example4:
    # # CustomerLHSServiceFAQ.dtl - provides Stuttgart specific HTML view for faq articles
    $Content =~ s{
        ^ \# [ ]                   # a hash at start of line followed by a space
        [\\/\w]+ \. \w{1,3}        # a filename with an extension
        (?:                        # the rest is optional
        [ ] - [ ]                  # separated by ' - '
        \w .+?                     # the description
        )?                         # end of optional part
        $                          # end of the current line
    }{}ixms;

    return $Content;
}

exit 0;
