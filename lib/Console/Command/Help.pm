# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Help;

use strict;
use warnings;

use System;

use parent qw(
    Console::BaseCommand
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Displays help for an existing command or search for commands.');
    $Self->AddArgument(
        Name => 'command',
        Description =>
            "Print usage information for this command (if command is available) or search for commands with similar names.",
        ValueRegex => qr/[a-zA-Z0-9:_]+/,
        Required   => 1,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $SearchCommand = $Self->GetArgument('command');
    my $CommandModule = 'Console::Command::' . $SearchCommand;

    # Is it an existing command? Then show help for it.
    if ( my $Command = System::ObjectInstanceCreate( $CommandModule, Silent => 1 ) ) {
        $Command->ANSI( $Self->ANSI() );
        print $Command->GetUsageHelp();
        return $Self->ExitCodeOk();
    }

    $Self->PrintError("Command $SearchCommand not found.");
    $Self->Print( $Self->GetUsageHelp() );
    return $Self->ExitCodeError();
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
