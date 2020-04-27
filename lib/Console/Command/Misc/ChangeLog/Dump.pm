# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Misc::ChangeLog::Dump;

use strict;
use warnings;

use Path::Tiny qw(path);

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Misc::ChangeLog::Dump - Console command to print the Change log in wiki friendly format.

=head1 DESCRIPTION

Print current change log entries into wiki format.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Print current change log entries into wiki format.');

    $Self->AddArgument(
        Name        => 'source-path',
        Description => "Specify the file with the change log.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddArgument(
        Name        => 'version',
        Description => "Specify specific version section in the change log.",
        Required    => 0,
        ValueRegex  => qr/\d+\.\d+\.\d+(?:\.\w+\d)?/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $SourcePath = $Self->GetArgument('source-path');

    if ( !-r $SourcePath ) {
        die "Couldn't open file $SourcePath\n";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Dumping change log entries...</yellow>\n\n");

    my $SourcePath = $Self->GetArgument('source-path');

    if ( !-e $SourcePath ) {
        $Self->PrintError("$SourcePath does not extists!");
    }
    if ( !-r $SourcePath ) {
        $Self->PrintError("Couldn't open file $SourcePath!");
    }

    my $Content = path($SourcePath)->slurp_raw();

    # Only current section.
    my $Section;

    my @Version = split /\./, ( $Self->GetArgument('version') || '' );

    my $SelectedSection = '\d+ \. \d+ \.';
    if (@Version) {
        $SelectedSection = join "\\.", @Version;
        $SelectedSection .= ' [ ]';
    }

    # Format in new style, markdown.
    if ( $Content =~ m{\A\#[ ]?\d} ) {
        ($Section) = $Content =~ m{ ( ^ \# [ ]? $SelectedSection .*? ) ^ \# [ ]? \d+ \. \d+ \. }smx;
        $Section //= '';

        # Generate wiki-style list, cut out dates.
        $Section =~ s{ ^ [ ] - [ ] \d{4}-\d{2}-\d{2} [ ] }{   * }smxg;

        # Format bug links.
        $Section
            =~ s{ (?:Fixed [ ])? bug\# \[( \d{4,6} )\]\(.*?\) }{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]]}ismxg;
    }

    # Format in old style.
    else {
        ($Section) = $Content =~ m{ ( ^ $SelectedSection .*? ) ^ \d+ \. \d+ \. }smx;

        $Section //= '';

        # Generate wiki-style list, cut out dates.
        $Section =~ s{ ^ [ ] - [ ] \d{4}-\d{2}-\d{2} [ ] }{   * }smxg;

        # Format bug links.
        $Section
            =~ s{ Fixed [ ] bug\# ( \d{4,6} ) }{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]]}ismxg;
    }

    # Mask WikiWords.
    $Section =~ s{(\s) ( [A-Z]+[a-z]+[A-Z]+[a-z]* ) }{$1!$2}smxg;

    # Mask HTML tags.
    $Section =~ s{<}{&lt;}smxg;
    $Section =~ s{>}{&gt;}smxg;

    # Mask markdown code delimiter.
    $Section =~ s{`}{=}smxg;

    $Self->Print($Section);

    $Self->Print("<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
