# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Module::File::Unlink;

use strict;
use warnings;

use File::Spec();

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::File::Unlink - Console command to unlink module files into a framework.

=head1 DESCRIPTION

Link OTRS module files into framework root.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Unlink module files from a framework root.');
    $Self->AddArgument(
        Name        => 'module',
        Description => "Specify a module directory or collection (specified in the /etc/config.pl file).",
        Required    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddArgument(
        Name        => 'framework-directory',
        Description => "Specify directory of the framework (default: \"./\").",
        Required    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'all',
        Description => "Remove all links from framework.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $RemoveAll = $Self->GetOption('all');
    my $Module    = $Self->GetArgument('module');

    if ( !$RemoveAll && !$Module ) {
        die "module or remove-all are needed!";
    }

    my @Directories;

    my $ModuleDirectory = File::Spec->rel2abs($Module);
    if ( !-e $ModuleDirectory || !-d $ModuleDirectory ) {
        my @Modules = @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
        if ( !@Modules ) {
            die "$Module is not a directory or a module collection";
        }
        @Directories = @Modules;
    }

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetArgument('framework-directory') || '.' );

    push @Directories, $FrameworkDirectory;

    for my $Directory (@Directories) {
        if ( !-e $Directory ) {
            die "$Directory does not exist";
        }
        if ( !-d $Directory ) {
            die "$Directory is not a directory";
        }
    }

    if ( !-e ( $FrameworkDirectory . '/RELEASE' ) ) {
        die "$FrameworkDirectory does not seem to be an OTRS framework directory";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    if ( $Self->GetOption('all') ) {
        return $Self->RemoveLinks();
    }
    else {
        return $Self->UnlinkModule();
    }
}

sub UnlinkModule {
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

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetArgument('framework-directory') || '.' );
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

        $Self->Print("\n<yellow>Unlinking $ModuleName module...</yellow>\n");

        my $Success = $Self->_UnlinkFiles(
            ModuleDirectory    => $ModuleDirectory,
            SourceDirectory    => $ModuleDirectory,
            FrameworkDirectory => $FrameworkDirectory,
        );

        if ( !$Success ) {
            $Self->PrintError("Can't unlink module.");
            $GlobalFail = 1;
            next MODULEDIRECTORY;
        }
    }

    if ($GlobalFail) {
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub RemoveLinks {
    my ($Self) = @_;

    $Self->Print("<yellow>Removing all links...</yellow>\n");

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetArgument('framework-directory') || '.' );

    my $Success = $Self->_UnlinkFiles(
        SourceDirectory    => $FrameworkDirectory,
        FrameworkDirectory => $FrameworkDirectory,
    );

    if ( !$Success ) {
        $Self->PrintError("Can't remove all links.");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub _UnlinkFiles {
    my ( $Self, %Param ) = @_;

    my $SourceDirectory = $Param{SourceDirectory};

    my $OrigDirectory = $SourceDirectory;
    my $DestDirectory = $SourceDirectory;

    if ( defined $Param{ModuleDirectory} ) {
        my $RelativeDirectory = $SourceDirectory =~ s{$Param{ModuleDirectory}}{}r;
        $DestDirectory = "$Param{FrameworkDirectory}/$RelativeDirectory";
    }

    # Check if there exists a link to the source directory. We need to clean this up separately.
    if ( -l "$DestDirectory" && -d "$DestDirectory" ) {

        # Remove link only if it points to our current source.
        if ( defined $Param{ModuleDirectory} ) {
            return 1 if readlink($DestDirectory) ne $OrigDirectory;
        }

        if ( !unlink($DestDirectory) ) {
            $Self->PrintError("Can't unlink directory symlink: $DestDirectory\n");
            return;
        }
        $Self->Print("  Directory link from $DestDirectory <green>removed</green>\n");

        # Restore target if there is a backup.
        if ( -d "$DestDirectory.old" ) {
            if ( !rename( "$DestDirectory.old", $DestDirectory ) ) {
                $Self->PrintError("Can't rename $DestDirectory.old to $DestDirectory: $!\n");
                return;
            }
            $Self->Print("    Restored original directory: <yellow>$DestDirectory</yellow>\n");
        }

        return 1;
    }

    my @List = glob("$SourceDirectory/*");

    return 1 if !@List;

    FILE:
    for my $File (@List) {
        $File =~ s{\/\/}{\/}g;

        next FILE if $File =~ m{^README.markdown$};
        next FILE if $File =~ m{^README.md$};
        next FILE if $File =~ m{^LICENSE$};

        # Recurse into subdirectories.
        if ( -d $File ) {
            my $Success = $Self->_UnlinkFiles(
                %Param,
                SourceDirectory => $File,
            );
            return if !$Success;
        }
        else {
            my $OrigFile = $File;
            my $DestFile;

            if ( defined $Param{ModuleDirectory} ) {
                $File =~ s{$Param{ModuleDirectory}}{};
                $DestFile = "$Param{FrameworkDirectory}/$File";
            }
            else {
                $File =~ s{$Param{FrameworkDirectory}}{};
                $DestFile = $OrigFile;
            }

            if ( -l $DestFile ) {
                if ( defined $Param{ModuleDirectory} ) {

                    # Remove link only if it points to our current source.
                    next FILE if readlink($DestFile) ne $OrigFile;
                }

                if ( !unlink($DestFile) ) {
                    $Self->PrintError("Can't unlink symlink: $DestFile\n");
                    return;
                }
                $Self->Print("  Link from $DestFile <green>removed</green>\n");

                # Restore target if there is a backup.
                if ( -f "$DestFile.old" ) {
                    if ( !rename( "$DestFile.old", $DestFile ) ) {
                        $Self->PrintError("Can't rename $DestFile.old to $DestFile: $!\n");
                        return;
                    }
                    $Self->Print("    Restored original file: <yellow>$DestFile</yellow>\n");
                }
            }
        }
    }

    return 1;
}

1;
