# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::Code::Reinstall;

use strict;
use warnings;

use File::Spec();

use base qw(Console::BaseCommand Console::BaseModule);

=head1 NAME

Console::Command::Module::Code::Reinstall - Console command to execute the <CodeRenstall> section of a module.

=head1 DESCRIPTION

Runs code reinstall part from a module .sopm file.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Run code reinstall from a module .sopm file.');
    $Self->AddArgument(
        Name        => 'module-file-path',
        Description => "Specify a module .sopm file.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    eval { require Kernel::Config };
    if ($@) {
        die "This console command needs to be run from a framework root directory!";
    }

    my $Module = $Self->GetArgument('module-file-path');

    # Check if .sopm file exists.
    if ( !-e "$Module" ) {
        die "Can not find file $Module!\n";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Running module code reinstall...</yellow>\n\n");

    my $Module = File::Spec->rel2abs( $Self->GetArgument('module-file-path') );

    # To capture the standard error.
    my $ErrorMessage = '';

    my $Success;

    {
        # Localize the standard error, everything will be restored after the block.
        local *STDERR;

        # Redirect the standard error to a variable.
        open STDERR, ">>", \$ErrorMessage;

        $Success = $Self->CodeActionHandler(
            Module => $Module,
            Action => 'Reinstall',
            Type   => 'post',
        );
    }

    $Self->Print("$ErrorMessage\n");

    if ( !$Success || $ErrorMessage =~ m{error}i ) {
        $Self->PrintError("Couldn't run code reinstall correctly from $Module");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
