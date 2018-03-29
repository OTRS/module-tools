# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::Database::Uninstall;

use strict;
use warnings;

use File::Spec();

use parent qw(Console::BaseCommand Console::BaseModule);

=head1 NAME

Console::Command::Module::Database::Uninstall - Console command to execute the <DatabaseUninstall> section of a module.

=head1 DESCRIPTION

Runs Database uninstall part from a module .sopm file.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Run database uninstall from a module .sopm file.');
    $Self->AddArgument(
        Name        => 'module-file-path',
        Description => "Specify a module .sopm file.",
        Required    => 1,
        HasValue    => 1,
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

    $Self->Print( "<yellow>Running module database uninstall (" . join( ',', @Types ) . ")...</yellow>\n\n" );

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
            $Success = $Self->DatabaseActionHandler(
                Module => $Module,
                Action => 'Uninstall',
                Type   => $Type,
            );
        }
    }

    $Self->Print("$ErrorMessage\n");

    if ( !$Success || $ErrorMessage =~ m{ERROR\:} ) {
        $Self->PrintError("Couldn't run database uninstall correctly from $Module");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();

}

1;
