#!/usr/bin/perl
# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
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

AddChangeLog.pl -b 1234 [-f CHANGES]
    Add bugzilla entry title to stable version CHANGES.md and commit message template.

AddChangeLog.pl -b 1234 --beta
    --beta causes the entry to be added to the latest version, even if it is not stable.

AddChangeLog.pl -m "My commit message."
    Add another message to CHANGES.md and commit message template.

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Cwd;
use Getopt::Long;
use Pod::Usage;
use Time::Piece;
use XMLRPC::Lite;

my ( $Help, $Bug, $Message, $Beta, $UserFile );
GetOptions(
    'h'    => \$Help,
    'b=s'  => \$Bug,
    'm=s'  => \$Message,
    'beta' => \$Beta,
    'f=s'  => \$UserFile,
);

if ( $Help || ( !$Bug && !$Message ) ) {
    pod2usage( -verbose => 0 );
}
UpdateChanges();

=item UpdateChanges()

Locates the CHANGES file, finds the correct spot to insert the change line.
Formats the line and inserts it to the correct location.

=cut

sub UpdateChanges {

    my $ChangesFile = $UserFile || '';

    if ( !$ChangesFile ) {

        FILE:
        for my $File (qw ( CHANGES.md CHANGES )) {
            if ( -e $File ) {
                $ChangesFile = $File;
                last FILE;
            }
        }

        # if no changes file was found maybe is a package path
        if ( !$ChangesFile ) {
            my $PackageName;

            $PackageName = cwd();

            $PackageName =~ s{.+/([^_|-]+)(:?[_|-].+)?$}{$1};

            # check for CHANGES-<PackageName>
            my $File = "CHANGES-$PackageName";
            if ( -e $File ) {
                $ChangesFile = $File;
            }

            # check for CHANGES-<PackageName>.md
            $File .= ".md";
            if ( -e $File ) {
                $ChangesFile = $File;
            }

            if ( !$ChangesFile ) {
                die "No CHANGES.md, CHANGES or $File file found in path.\n";
            }
        }
    }

    my $ChangeLine;
    my $Summary;

    # If bug does not exist, this will stop the script.
    if ($Bug) {
        $Summary = GetBugSummary($Bug);
        $ChangeLine = FormatChangesLine( $Bug, $Summary, $ChangesFile );
    }
    elsif ($Message) {
        $Summary = $Message;
        $ChangeLine = FormatChangesLine( '', $Message, $ChangesFile );
    }

    # read in existing changes file
    open my $InFile, '<', $ChangesFile || die "Couldn't open $ChangesFile: $!";    ## no critic
    binmode $InFile;
    my @Changes = <$InFile>;
    close $InFile;

    # write out new file with added line
    open my $OutFile, '>', $ChangesFile || die "Couldn't open $ChangesFile: $!";    ## no critic
    binmode $OutFile;

    my $Printed            = 0;
    my $ReleaseHeaderFound = 0;
    my $ReleaseHeaderRegex = qr{^[#]?\d+[.]\d+[.]\d+[ ]};                           # 1.2.3
    if ($Beta) {
        $ReleaseHeaderRegex = qr{^[#]?\d+[.]\d+[.]\d+};                             # 1.2.3.beta3
    }
    for my $Line (@Changes) {
        if ( !$ReleaseHeaderFound && $Line =~ m{$ReleaseHeaderRegex} ) {
            $ReleaseHeaderFound = 1;
        }

        if ( $ReleaseHeaderFound && !$Printed && $Line =~ m/^(\s+-\s+|$)/smx ) {
            print $OutFile $ChangeLine;
            $Printed = 1;
        }
        print $OutFile $Line;
    }
    close $OutFile;

    ## no critic
    open $OutFile, '>',
        '.git/OTRSCommitTemplate.msg' || die "Couldn't open .git/OTRSCommitTemplate.msg: $!";
    ## use critic
    binmode $OutFile;
    if ($Bug) {
        print $OutFile "Fixed: $Summary (bug#$Bug).\n";
    }
    elsif ($Message) {
        print $OutFile "$Message\n";
    }
    close $OutFile;

    return 1;
}

sub GetBugSummary {
    my $Bug = shift;

    # get bug description from bug tracker
    # if bug does not exist we automatically get an error message and the script dies
    my $Proxy  = XMLRPC::Lite->proxy('http://bugs.otrs.org/xmlrpc.cgi');
    my $Result = $Proxy->call(
        'Bug.get',
        {
            ids => [$Bug],
        },
    )->result();
    if ( !$Result || !$Result->{bugs} || !@{ $Result->{bugs} } ) {
        die "Could not find Bug $Bug.\n";
    }

    my $Summary = $Result->{bugs}->[0]->{summary};

    # Remove trailing dot if present.
    if ($Summary) {
        $Summary =~ s{[.]+$}{}smx;

    }
    return $Summary;
}

=item FormatChangesLine()

Takes as arguments bug# and name of the changes file.
Looks up the description for the given bug# in Bugzilla.
Generates the change log entry and depending on the format of the CHANGES
file (Markdown or not) generates a properly formatted entry and returns this.

=cut

sub FormatChangesLine {

    my $Bug         = shift;
    my $Summary     = shift;
    my $ChangesFile = shift;

    # get todays date as iso format (yyyy-mm-dd)
    my $Time = localtime;      ## nofilter(TidyAll::Plugin::OTRS::Perl::Time)
    my $Date = $Time->ymd();

# formatting is different for markdown files; below first 'regular', second 'markdown'.
# - 2013-03-02 Fixed bug#9214 - IE10: impossible to open links from rich text articles.
# - 2013-03-02 Fixed bug#[9214](http://bugs.otrs.org/show_bug.cgi?id=9214) - IE10: impossible to open links from rich text articles.

    # format for CHANGES (OTRS 3.1.x and earlier) is different from CHANGES.md
    my $Line;
    if ( $Bug && $ChangesFile ne 'CHANGES.md' ) {
        $Line = " - $Date Fixed bug#$Bug - $Summary.\n";
    }
    elsif ($Bug) {
        $Line = " - $Date Fixed bug#[$Bug](http://bugs.otrs.org/show_bug.cgi?id=$Bug) - $Summary.\n";
    }
    elsif ($Message) {
        $Line = " - $Date $Summary\n";
    }
    return $Line;
}
