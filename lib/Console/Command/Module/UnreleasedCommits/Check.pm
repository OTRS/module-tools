# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::UnreleasedCommits::Check;

use strict;
use warnings;

use File::Spec ();
use Encode;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::UnreleasedCommits::Check - Console command to check if a module has commits after the last tag

=head1 DESCRIPTION

Warns if a module have commits after latest tag (release).

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Checks if a module requires a new release due to commits after last tag.');
    $Self->AddArgument(
        Name        => 'module',
        Description => "Specify a module directory or collection (specified in the /etc/config.pl file).",
        Required    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'parent-directory',
        Description => "Specify a parent directory containing modules.",
        Required    => 0,
        HasValue    => 1,
        Multiple    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'verbose',
        Description => "Print detailed command output.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'show-ok',
        Description => "Print also results from modules with no commits after last tag.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $Module          = $Self->GetArgument('module');
    my $ModuleDirectory = File::Spec->rel2abs($Module);
    if ( !-e $ModuleDirectory || !-d $ModuleDirectory ) {
        my @Modules = @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
        if ( !@Modules ) {
            die "$Module is not a directory or a module collection";
        }
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my @Directories;

    my $Module               = $Self->GetArgument('module');
    my $ModuleDirectoryParam = File::Spec->rel2abs($Module);

    my $ParentDirectory = $Self->GetOption('parent-directory');

    if ( -e $ModuleDirectoryParam && !$ParentDirectory->[0] ) {
        push @Directories, $ModuleDirectoryParam;
    }
    elsif ($Module) {
        @Directories = @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
    }

    # TODO: This could be in a base class, reusable for other commands.
    if ( ref $ParentDirectory eq 'ARRAY' ) {

        PARENTDIRECTORYVALUE:
        for my $ParentDirectoryValue ( @{$ParentDirectory} ) {

            next PARENTDIRECTORYVALUE if !$ParentDirectoryValue;

            my $ParentDirectoryValue = File::Spec->rel2abs($ParentDirectoryValue);

            if ( !-d $ParentDirectoryValue ) {
                $Self->PrintError("Package directory '$ParentDirectoryValue' is not a directory path!\n");
                next PARENTDIRECTORYVALUE;
            }

            if ( !-r $ParentDirectoryValue ) {
                $Self->PrintError("Package directory '$ParentDirectoryValue' is not readable!\n");
                next PARENTDIRECTORYVALUE;
            }

            # get all (package-)directories
            my @FilesInDirectory = $Self->DirectoryRead(
                Directory => $ParentDirectoryValue,
                Filter    => '*',
            );

            MODULEDIRECTORY:
            for my $ModuleDirectory (@FilesInDirectory) {

                # Look if an sopm exists.
                my @SOPMs = glob "$ModuleDirectory/*.sopm";

                if ( !@SOPMs || !$SOPMs[0] ) {
                    next MODULEDIRECTORY;
                }

                push @Directories, $ModuleDirectory;
            }
        }
    }

    $Self->Print("<yellow>Checking modules...</yellow>\n\n");

    MODULEDIRECTORY:
    for my $ModuleDirectory ( sort { "\L$a" cmp "\L$b" } @Directories ) {

        # check if its a framework directory
        if ( -e $ModuleDirectory . '/RELEASE' ) {
            next MODULEDIRECTORY;
        }

        # Look if an SOPM exists.
        my @SOPMs = glob "\"$ModuleDirectory/*.sopm\"";

        if ( !@SOPMs || !$SOPMs[0] ) {
            $Self->PrintError("Couldn't find the SOPM file in $ModuleDirectory");
            return $Self->ExitCodeError();
        }

        my $ModuleName = $SOPMs[0];
        $ModuleName =~ s{$ModuleDirectory/(.*)\.sopm}{$1}i;

        my $Branch = `cd $ModuleDirectory && git rev-parse --abbrev-ref HEAD`;
        $Branch =~ s{\s+}{}msxg;

        my $Output = "  $ModuleDirectory <yellow>($ModuleName $Branch)</yellow> ...";

        if ( $Branch ne "master" && $Branch !~ m{\Arel-}msxi ) {
            $Output .= " <red>Not a release branch!</red>\n";
            $Self->Print($Output);
            next MODULEDIRECTORY;
        }
        my $Result = `cd $ModuleDirectory && git log \`git describe --tags --abbrev=0\`..HEAD --oneline`;
        if ($Result) {
            $Output .= " <red>Release needed!</red>\n";
            if ( $Self->GetOption('verbose') ) {
                $Result =~ s{^}{    }mg;
                $Output .= $Result;
            }
            $Self->Print($Output);
            next MODULEDIRECTORY;
        }

        if ( $Self->GetOption('show-ok') ) {

            $Self->Print("$Output <green>OK</green>\n");
        }
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
