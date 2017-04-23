# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::File::Cleanup;

use strict;
use warnings;

use File::Spec();

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::File::Link - Console command to to remove not needed files form a module.

=head1 DESCRIPTION

Removed unwanted files from a module directory such as .DS_Store or Kernel/Language/*.pm.old.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Removes not needed files from a module.');
    $Self->AddArgument(
        Name        => 'module',
        Description => "Specify a module directory or collection (specified in the /etc/config.pl file).",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my @Directories;

    my $Module          = $Self->GetArgument('module');
    my $ModuleDirectory = File::Spec->rel2abs($Module);
    if ( !-e $ModuleDirectory || !-d $ModuleDirectory ) {
        my @Modules = @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
        if ( !@Modules ) {
            die "$Module is not a directory or a module collection";
        }
        @Directories = @Modules;
    }

    for my $Directory (@Directories) {
        if ( !-e $Directory ) {
            die "$Directory does not exist";
        }
        if ( !-d $Directory ) {
            die "$Directory is not a directory";
        }
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my @Directories;

    my $Module               = $Self->GetArgument('module');
    my $ModuleDirectoryParam = File::Spec->rel2abs($Module);
    if ( -e $ModuleDirectoryParam ) {
        push @Directories, $ModuleDirectoryParam;
    }
    else {
        @Directories = @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
    }

    my $GlobalFail;

    MODULEDIRECTORY:
    for my $ModuleDirectory (@Directories) {

        # Look if an sopm exists.
        my @SOPMs = glob "$ModuleDirectory/*.sopm";

        if ( !@SOPMs || !$SOPMs[0] ) {
            $Self->PrintError("Couldn't find the SOPM file in $ModuleDirectory");
        }

        my $ModuleName = $SOPMs[0] || '';
        if ($ModuleName) {
            $ModuleName =~ s{$ModuleDirectory/(.*)\.sopm}{$1}i;
        }

        $Self->Print("\n<yellow>Removing files from $ModuleName module...</yellow>\n");

        my $Success = $Self->_Cleanup(
            ModuleDirectory => $ModuleDirectory,
            SourceDirectory => $ModuleDirectory,
        );

        if ( !$Success ) {
            $Self->PrintError("Can't cleanup module.");
            $GlobalFail = 1;
            next MODULEDIRECTORY;
        }
    }

    if ($GlobalFail) {
        return $Self->ExitCodeError();
    }

    $Self->Print("<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub _Cleanup {
    my ( $Self, %Param ) = @_;

    my $SourceDirectory = $Param{SourceDirectory};

    my @List = glob("$SourceDirectory/* $SourceDirectory/.*");

    FILE:
    for my $File (@List) {
        $File =~ s{\/\/}{\/}g;

        next FILE if $File =~ m{\.\z}msx;
        next FILE if $File =~ m{\.\.\z}msx;
        next FILE if $File =~ m{\.git}msx;

        # Recurse into subdirectories.
        if ( -d $File ) {
            my $Success = $Self->_Cleanup(
                %Param,
                SourceDirectory => $File,
            );
            return if !$Success;
        }
        else {
            my $Match;
            if (
                $File =~ m{\.DS_Store\z}msx
                || $File =~ m{Kernel/Language/.+\.pm\.old\z}msx
                )
            {
                $Match = 1;
            }

            next FILE if !$Match;

            if ( -l "$File" ) {
                $Self->Print("  $File is a symlink <green>Skipped</green>\n");
                next FILE;
            }

            my $Success = unlink("$File");
            if ( !$Success ) {
                $Self->PrintError("  Can't remove: $File!\n");
                return;
            }

            $Self->Print("  Removed $File <green>OK</green>\n");
        }
    }

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
