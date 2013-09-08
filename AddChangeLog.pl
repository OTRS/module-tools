#!/usr/bin/perl
# --
# module-tools/AddChangeLog.pl
#   - script for adding entries to change log
# Copyright (C) 2001-2013 OTRS AG, http://otrs.org/
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

AddChangeLog.pl - script for adding change log entries

=head1 SYNOPSIS

AddChangeLog.pl -b 1234
ChangeLog with bugzilla entry number

=head1 DESCRIPTION

Please send any questions, suggestions & complaints to <dev-support@otrs.com>

=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Time::Piece;
use WWW::Bugzilla3;

my ( $Help, $Bug );
GetOptions(
    'h'   => \$Help,
    'b=s' => \$Bug,
);
pod2usage( -verbose => 0 ) if $Help || !$Bug;
UpdateChanges();

=item UpdateChanges()

Locates the CHANGES file, finds the correct spot to insert the change line.
Formats the line and inserts it to the correct location.

=cut

sub UpdateChanges {

    my $ChangesFile;
    for my $File ( qw ( CHANGES.md CHANGES ) ){
        if ( -e $File ) {
            $ChangesFile = $File;
            last;
        }
    }
    if ( !$ChangesFile ) {
        die "No CHANGES.md or CHANGES file found in path.\n";
    }

    # format Change line. If bug does not exist, this will stop the script.
    my $ChangeLine = FormatChangesLine($Bug, $ChangesFile);

    # read in existing changes file
    open my $InFile, '<', $ChangesFile || die "Couldn't open $ChangesFile: $!";
    binmode $InFile;
    my @Changes = <$InFile>;
    close $InFile;

    # write out new file with added line
    open my $OutFile, '>', $ChangesFile || die "Couldn't open $ChangesFile: $!";
    binmode $OutFile;

    my $Printed = 0;
    for my $Line ( @Changes ) {
        if (!$Printed && $Line =~ /^ - / ) {
            print $OutFile $ChangeLine;
            $Printed = 1;
        }
        print $OutFile $Line;
    }
    close $OutFile;

    # TODO maybe prepare git log message, add CHANGES to staged files.
    return 1;
}

=item FormatChangesLine()

Takes as arguments bug# and name of the changes file.
Looks up the description for the given bug# in Bugzilla.
Generates the change log entry and depending on the format of the CHANGES
file (Markdown or not) generates a properly formatted entry and returns this.

=cut

sub FormatChangesLine {

    my $Bug = shift;
    my $ChangesFile = shift;

    # get bug description from bug tracker
    # if bug does not exist we automatically get an error message and the script dies
    my $Bugzilla = new WWW::Bugzilla3(site => 'bugs.otrs.org');
    my @BugInfo = $Bugzilla->get_bugs( $Bug );
    my $Description = $BugInfo[0]->{summary};

    # get todays date as iso format (yyyy-mm-dd)
    my $Time = localtime;
    my $Date = $Time->ymd();

    # formatting is different for markdown files; below first 'regular', second 'markdown'.
    # - 2013-03-02 Fixed bug#9214 - IE10: impossible to open links from rich text articles.
    # - 2013-03-02 Fixed bug#[9214](http://bugs.otrs.org/show_bug.cgi?id=9214) - IE10: impossible to open links from rich text articles.

    # format for CHANGES (OTRS 3.1.x and earlier) is different from CHANGES.md
    my $Line;
    if ( $ChangesFile eq 'CHANGES' ) {
        $Line = " - $Date Fixed bug#$Bug - $Description.\n";    }
    else {
        $Line = " - $Date Fixed bug#[$Bug](http://bugs.otrs.org/show_bug.cgi?id=$Bug) - $Description.\n";
    }
    return $Line;
}
