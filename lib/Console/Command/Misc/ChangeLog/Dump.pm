# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Misc::ChangeLog::Dump;

use strict;
use warnings;

use base qw(Console::BaseCommand);

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

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $SourcePath = $Self->GetArgument('source-path');

    if ( !-r $SourcePath ) {
        die "Cannot open file $SourcePath\n";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Dumping change log entries...</yellow>\n\n");

    my $SourcePath = $Self->GetArgument('source-path');

    my $FH;
    my $Success = open( $FH, '<', $SourcePath );    ## no critic
    if ( !$Success ) {
        $Self->PrintError('Cannot open file');
        return $Self->ExitCodeError();
    }

    my $Content = join( '', <$FH> );

    close($FH);

    # Only current section.
    my $Section;

    # Format in new style, markdown.
    if ( $Content =~ m{\A\#\d} ) {
        ($Section) = $Content =~ m{ ( ^ \# \d+ \. \d+ \. .*? ) ^ \# \d+ \. \d+ \. }smx;

        # Generate wiki-style list, cut out dates.
        $Section =~ s{ ^ [ ] - [ ] \d{4}-\d{2}-\d{2} [ ] }{   * }smxg;

        # Format bug links.
        $Section
            =~ s{ (?:Fixed [ ])? bug\# \[( \d{4,6} )\]\(.*?\) }{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]]}ismxg;
    }

    # Format in old style.
    else {
        ($Section) = $Content =~ m{ ( ^ \d+ \. \d+ \. .*? ) ^ \d+ \. \d+ \. }smx;

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

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
