#!/usr/bin/perl -w
# --
# module-tools/module_check.pl - script to check OTRS modules
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
# --
# $Id: module_check.pl,v 1.22 2012-01-21 14:26:20 sb Exp $
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

use vars qw($VERSION);
$VERSION = qw($Revision: 1.22 $) [1];

# get options
my %Opts = ();
getopt('omd', \%Opts);

# set default
if (!$Opts{'o'} || !$Opts{'m'} ) {
    $Opts{'h'} = 1;
}
if ( $Opts{'h'} ) {
    print "module_check.pl <Revision $VERSION> - Check OTRS modules\n";
    print "Copyright (C) 2001-2012 OTRS AG, http://otrs.org/\n";
    print "usage: module_check.pl -o <Original-Framework-Path> -m <Module-Path> -v [verbose mode] -d [debug mode 1] [diff options: -u|-b|-B|-w]\n\n";
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
    $OriginalFile =~ s{ /Kernel/Custom }{}xms;
    $OriginalFile =~ s{ /Custom }{}xms;
    $OriginalFile .= $OriginalFilename;
    $OriginalFile  =~ s{\s}{}xms;

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
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
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
    open my $FH, '<', $Param{File} or die "could not open file $Param{File}\n";
    my $Content = do { local $/; <$FH> };
    close $FH;

    # prevent checking of files with nested markers (markers within markers)
    if ( $Content =~ m{
        (
            ^ [ \t]* \# [ ] --- [ \t]* \n
            ^ [ \t]* \# [ ] [^\n ][^\n]+ \n
            ^ [ \t]* \# [ ] --- [ \t]* \n
            (?: (?! ^ [ \t]* \# [ ] --- [ \t]* \n ). )+
            ^ [ \t]* \# [ ] --- [ \t]* \n
            ^ [ \t]* \# [ ] [^\n ][^\n]+ \n
            ^ [ \t]* \# [ ] --- [ \t]* \n
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
        ^ [ \t]* \# [ ] --- [ \t]*
    }{---PLACEHOLDER---}xms
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

    # delete ID line
    $Content =~ s{ ^ \# [ ] \$Id: [^\n]+ \n }{}xms;

    # replace OldId with Id and remember Id-Line for possible occurance in perldoc
    $Content =~ s{ ^ \# [ ] \$OldId: ( [^\n]+ ) }{\# \$Id: module_check.pl,v 1.22 2012-01-21 14:26:20 sb Exp $1}xms;

    # replace possible occurances of $Id: in perldoc
    my $IdLine = $1 || '';
    $Content =~ s{ ^ \$Id: module_check.pl,v 1.22 2012-01-21 14:26:20 sb Exp $Id:$IdLine}xmsg;

    # clean the content
    $Content = ContentClean( Content => $Content );

    return $Content;
}

=item OriginalFilenameGet

No documentation yet.

=cut

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

=item ContentClean

No documentation yet.

=cut

sub ContentClean {
    my (%Param) = @_;

    my $Content = $Param{Content};

    # delete the different version lines

    # example1: $VERSION = qw($Revision: 1.22 $) [1];
    $Content =~ s{ ^ \$VERSION [ ] = [ ] qw \( \$[R]evision: [ ] .+? $ }{}ixms;

    # example2: $VERSION = '$Revision: 1.22 $';
    $Content =~ s{ ^ \$VERSION [ ] = [ ] '     \$[R]evision: [ ] .+? $ }{}ixms;

    # example3:
    #=head1 VERSION
    #
    #$Revision: 1.22 $ $Date: 2012-01-21 14:26:20 $
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

    # Delete the standard comment with the filenname and a description.
    # The name of the file could have changed.
    # example4:
    # # CustomerLHSServiceFAQ.dtl - provides Stuttgart specific HTML view for faq articles
    $Content =~ s{
        ^ \# [ ]                   # a hash at start of line followed by a space
        [\\/\w]+ \. \w{1,3}        # a filename with an extension
        [ ] - [ ]                  # separated by ' - '
        \w .+? $                   # the description till the end of the current line
    }{}ixms;

    return $Content;
}

exit 0;

=back

=head1 KNOWN LIMITATIONS

False negatives might be reported when the first line of the new content starts with an '#'.

=head1 SEE ALSO

L<https://wiki.otrs.com/twiki/bin/view/Development/KennzeichnungVonCodestellenAngepassterOTRS-Framework-Dateien>

=cut
