# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::File::Link;

use strict;
use warnings;

use File::Spec();

use base qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::File::Link - Console command to link module files into a framework.

=head1 DESCRIPTION

Link OTRS module files into framework root.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Link module files into a framework root.');
    $Self->AddArgument(
        Name        => 'module',
        Description => "Specify a module directory or collection (specified in the /etc/config.pl file).",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddArgument(
        Name        => 'framework-directory',
        Description => "Specify directory of the framework (default: \"./\").",
        Required    => 0,
        ValueRegex  => qr/.*/smx,
    );

    my $Name = $Self->Name();

    $Self->AdditionalHelp(<<"EOF");
The <green>otrs.Console.pl $Name</green> comand installs a given OTRS module into the OTRS framework by creating appropriate links.

Beware that code from the .sopm file is not executed.

Existing files are backupped by adding the extension '.old'.

So this script can be used for an already installed module, when linking files from git checkout directory.
EOF

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

    if ( !-e $FrameworkDirectory . '/RELEASE' ) {
        die "$FrameworkDirectory does not seams to be an OTRS framework directory";
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

        $Self->Print("\n<yellow>Linking $ModuleName module...</yellow>\n");

        my $Success = $Self->_Link(
            ModuleDirectory    => $ModuleDirectory,
            SourceDirectory    => $ModuleDirectory,
            FrameworkDirectory => $FrameworkDirectory,
        );

        if ( !$Success ) {
            $Self->PrintError("Can't link module.");
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

sub _Link {
    my ( $Self, %Param ) = @_;

    my $SourceDirectory = $Param{SourceDirectory};

    my @List = glob("$SourceDirectory/*");

    FILE:
    for my $File (@List) {
        $File =~ s{\/\/}{\/}g;

        next FILE if $File =~ m{^README.markdown$};
        next FILE if $File =~ m{^README.md$};
        next FILE if $File =~ m{^LICENSE$};

        # Recurse into subdirectories.
        if ( -d $File ) {
            my $Success = $Self->_Link(
                %Param,
                SourceDirectory => $File,
            );
            return if !$Success;
        }
        else {
            my $OrigFile = $File;
            $File =~ s{$Param{ModuleDirectory}}{};

            my $DestFile = "$Param{FrameworkDirectory}/$File";

            # check directory of location (in case create a directory)
            if ( "$DestFile" =~ m{^(.*)\/(.+?|)$} )
            {
                my $Directory        = $1;
                my @Directories      = split( /\//, $Directory );
                my $DirectoryCurrent = '';
                for my $Directory (@Directories) {
                    $DirectoryCurrent .= "/$Directory";
                    if ( $DirectoryCurrent && !-d $DirectoryCurrent ) {
                        if ( mkdir $DirectoryCurrent ) {
                            $Self->Print("  Create Directory <yellow>$DirectoryCurrent</yellow>\n");
                        }
                        else {
                            $Self->PrintError("Can't create directory $DirectoryCurrent: $!\n");
                            return;
                        }
                    }
                }
            }

            if ( -l "$DestFile" ) {

                # Skip if already linked correctly.
                if ( readlink($DestFile) eq $OrigFile ) {
                    $Self->Print("  Link from $DestFile is <green>OK</green>\n");
                    next FILE;
                }

                my $Success = unlink("$DestFile");
                if ( !$Success ) {
                    $Self->PrintError("  Can't unlink symlink: $DestFile!\n");
                    return;
                }
            }

            if ( -e "$DestFile" ) {
                if ( rename( "$DestFile", "$DestFile.old" ) ) {
                    $Self->Print("  Backup: <yellow>$DestFile.old</yellow>\n");
                }
                else {
                    $Self->PrintError("Can't rename $DestFile to $DestFile.old!\n");
                    return;
                }
            }

            if ( !-e $OrigFile ) {
                $Self->PrintError("No such orig file: $OrigFile");
            }
            elsif ( !symlink( $OrigFile, "$DestFile" ) ) {
                $Self->PrintError("Can't $File link: $!");
            }
            else {
                $Self->Print("  Link: $OrigFile -> \n");
                $Self->Print("        <green>$DestFile</green>\n");
            }
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
