# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Module::Code::Uninstall;

use strict;
use warnings;

use File::Spec();

use parent qw(Console::BaseCommand Console::BaseModule);

=head1 NAME

Console::Command::Module::Code::Uninstall - Console command to execute the <CodeUninstall> section of a module.

=head1 DESCRIPTION

Runs code uninstall part from a module .sopm file.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Run code uninstall from a module .sopm file.');
    $Self->AddArgument(
        Name        => 'module-file-path',
        Description => "Specify a module .sopm file.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddArgument(
        Name        => 'type',
        Description => "Specify if only 'pre' or 'post' type should be executed.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/\A(?:pre|post)\z/smx,
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

    my @Types;
    if ( $Self->GetArgument('type') ) {
        @Types = ( $Self->GetArgument('type') );
    }
    else {
        @Types = ( 'pre', 'post' );
    }

    $Self->Print( "<yellow>Running module code uninstall (" . join( ',', @Types ) . ")...</yellow>\n\n" );

    my $Module = File::Spec->rel2abs( $Self->GetArgument('module-file-path') );

    # To capture the standard error.
    my $ErrorMessage = '';

    my $Success;

    {
        # Localize the standard error, everything will be restored after the block.
        local *STDERR;

        # Redirect the standard error to a variable.
        open STDERR, ">>", \$ErrorMessage;

        for my $Type (@Types) {
            $Success = $Self->CodeActionHandler(
                Module => $Module,
                Action => 'Uninstall',
                Type   => $Type,
            );
        }
    }

    $Self->Print("$ErrorMessage\n");

    if ( !$Success || $ErrorMessage =~ m{error}i ) {
        $Self->PrintError("Couldn't run code uninstall correctly from $Module");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
