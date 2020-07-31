# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Misc::Translations::Sync;

use strict;
use warnings;

use Cwd qw(cwd);
use File::Spec();
use IPC::Cmd qw[can_run run];
use IPC::Open3;
use Fcntl qw(:flock);

use Console::Command::Module::File::Link;
use Console::Command::Module::File::Unlink;
use Console::Command::Misc::ChangeLog::Add;
use Console::Command::Module::File::Cleanup;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Misc::Translations::Sync - Console command to syncronuze framework and packages translations using C<Weblate> client.

=head1 DESCRIPTION
Syncrhonize framework and packages translations using C<Weblate> client..

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Sync frameork or package translation files using weblate client.');

    $Self->AddOption(
        Name        => 'framework-directory',
        Description => "Specify the framework directory to use its own translations tools.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'target-directory',
        Description => "Specify framework or module directory to update the translations from.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'po-only',
        Description => "To only update .po files.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'pm-only',
        Description => "To only update .pm files.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    my $Name = $Self->Name();

    $Self->AdditionalHelp(<<"EOF");
The <green>$Name</green> command fully synchronize all translation files from the framework or package by doing the following steps:

 1  Commit and push the translations (.po files) from translate.otrs.com into the main stream.
 2  Pull main stream changes into the local clone.
 3  Link package files with a framework. (Only for packages).
 4  Delete framework cache and rebuild the configuration.
 5  Update runtime translations (.pm files) and translation source (.pot file).
 6  Unlink package files from the framework. (Only for packages).
 7  Delete framework cache and rebuild the configuration.
 8  Write an entry in CHANGES.md file. (Only for framework).
 9  Commit and push the translations (.pm and pot files) and for the framework also CHANGES.md from local clone to the main stream.
 10 Pull main stream changes into translate.otrs.com.

<yellow>Usage:</yellow>
From framework root directory translate framework:
 <green>otrs.ModuleTools.pl $Self->{Name}</green>

From framework root directory translate package:
 <green>otrs.ModuleTools.pl $Self->{Name}</green> --target-directory <yellow>/ws/<package_name_version></yellow>

From package root directory translate package:
 <green>otrs.ModuleTools.pl $Self->{Name}</green> --framework-directory <yellow>/ws/<framework_version></yellow>

<red>Known issues:</red>
<red>*</red> .pot file is always written by the framework with the current date even if there are no changes in the content.
<red>*</red> CHANGES.md new entry is written in the first section and this could be wrong and has to be manually fixed before commit and push.

EOF
    return;
}

sub PreRun {
    my ($Self) = @_;

    # TODO: also check for wl client.
    my $ClientPath = can_run('wlc');
    if ( !$ClientPath ) {
        die "wlc was not found, install it with: \npip3 install wlc\n\n";
    }

    # Get framework path or use current.
    my $FrameworkDirectory = $Self->GetOption('framework-directory');
    if ( !$FrameworkDirectory ) {
        $FrameworkDirectory = cwd;
    }
    if ( !-e "$FrameworkDirectory/RELEASE" ) {
        die "Framework directory: '$FrameworkDirectory' does not seams to be valid.\n\n";
    }

    # Get target path or use framework path or use current.
    my $TargetDirectory = $Self->GetOption('target-directory');
    if ( !$TargetDirectory && $Self->GetOption('framework-directory') ) {
        $TargetDirectory = cwd;
    }
    $TargetDirectory ||= $FrameworkDirectory;

    my @SOPMs = glob "$TargetDirectory/*.sopm";
    if (
        !-e "$TargetDirectory/RELEASE"
        && !$SOPMs[0],
        )
    {
        die "Target direcotry: $TargetDirectory does not seams to be a valid OTRS framework or package directory.\n\n";
    }

    if ( !-e "$TargetDirectory/.weblate" ) {
        die "Target direcotry: $TargetDirectory does not contain a Weblate configuration file.\n\n";
    }

    my $POOnly = $Self->GetOption('po-only');
    my $PMOnly = $Self->GetOption('pm-only');

    if ( $POOnly && $PMOnly ) {
        die "--po-only and --pm-only can not be used at the same time";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my $ClientPath = can_run('wlc');

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );
    if ( !$FrameworkDirectory ) {
        $FrameworkDirectory = cwd;
    }

    my $TargetDirectory = $Self->GetOption('target-directory');
    if ( !$TargetDirectory && $Self->GetOption('framework-directory') ) {
        $TargetDirectory = cwd;
    }
    $TargetDirectory ||= $FrameworkDirectory;
    $TargetDirectory = File::Spec->rel2abs($TargetDirectory);

    my $IsFrameworkTranslation = ( -e "$TargetDirectory/RELEASE" ) ? 1 : 0;

    my $POOnly = $Self->GetOption('po-only');
    my $PMOnly = $Self->GetOption('pm-only');

    # Flush ARGV so inputs from user works
    while (@ARGV) {
        shift @ARGV;
    }

    if ( !$PMOnly ) {
        my $Success = $Self->UpdatePOFiles(
            ClientPath      => $ClientPath,
            TargetDirectory => $TargetDirectory,
        );
        if ( !$Success ) {
            $Self->Print("\n<red>Fail.</red>\n");
            return $Self->ExitCodeError();
        }

        if ($POOnly) {
            $Self->Print("\n<green>Done.</green>\n");
            return $Self->ExitCodeOk();
        }
    }

    if ( !$IsFrameworkTranslation ) {
        my $Success = $Self->RunModule(
            Message => 'Linking module with framework',
            Module  => 'Console::Command::Module::File::Link',
            Params  => [ $TargetDirectory, $FrameworkDirectory ],
            Silent  => 1,
        );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    my @Tasks = (
        {
            Message => 'Deleting Framework cache',
            Command => "$FrameworkDirectory/bin/otrs.Console.pl Maint::Cache::Delete",
            Silent  => 1,
        },
        {
            Message => 'Rebuilding Framework configuration',
            Command => "$FrameworkDirectory/bin/otrs.Console.pl Maint::Config::Rebuild --cleanup",
            Silent  => 1,
        },
    );

    my $TranslatOptions = $IsFrameworkTranslation ? '' : "--module-directory $TargetDirectory";
    push @Tasks, {
        Message => 'Generating Framework translations (please wait)',
        Command => "$FrameworkDirectory/bin/otrs.Console.pl Dev::Tools::TranslationsUpdate $TranslatOptions",
    };

    TASK:
    for my $Task (@Tasks) {
        my $Success = $Self->System( %{$Task} );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    if ($IsFrameworkTranslation) {

        # TODO: Requires update in Change:LogAdd
        # my $Version = $Self->FrameworkVersionGet(FrameworkDirectory => $FrameworkDirectory);

        my $Success = $Self->RunModule(
            Message => 'Adding message to CHANGES.md file',
            Module  => 'Console::Command::Misc::ChangeLog::Add',
            Params  => [
                '--message', 'Updated translations, thanks to all translators.',

                #    '--version', $Version,
            ],
            Silent => 1,
        );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }
    else {
        my $Success = $Self->RunModule(
            Message => 'Un-linking module with framework',
            Module  => 'Console::Command::Module::File::Unlink',
            Params  => [ $TargetDirectory, $FrameworkDirectory ],
            Silent  => 1,
        );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
        @Tasks = (
            {
                Message => 'Deleting Framework cache (after package removal)',
                Command => "$FrameworkDirectory/bin/otrs.Console.pl Maint::Cache::Delete",
                Silent  => 1,
            },
            {
                Message => 'Rebuilding Framework configuration (after package removal)',
                Command => "$FrameworkDirectory/bin/otrs.Console.pl Maint::Config::Rebuild --cleanup",
                Silent  => 1,
            },
        );

        TASK:
        for my $Task (@Tasks) {
            $Success = $Self->System( %{$Task} );
            if ( !$Success ) {
                return $Self->ExitCodeError();
            }
        }

        $Success = $Self->RunModule(
            Message => 'Cleaningup module for unneeded files',
            Module  => 'Console::Command::Module::File::Cleanup',
            Params  => [$TargetDirectory],
        );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    @Tasks = (
        {
            Message => 'Staging Local translations (.pot file)',
            Command => "cd $TargetDirectory && git add i18n",
        },
        {
            Message => 'Staging Local translations (.pm files)',
            Command => "cd $TargetDirectory && git add Kernel/Language",
        },
    );

    if ($IsFrameworkTranslation) {
        unshift @Tasks, {
            Message => 'Staging Local CHANGES.md file',
            Command => "cd $TargetDirectory && git add CHANGES.md",
        };
    }

    TASK:
    for my $Task (@Tasks) {
        my $Success = $Self->System( %{$Task} );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    $Self->Print("\nPlease review the .pm files\n");
    $Self->Print("Manually run OTRS Code policy... \n");
    $Self->Print("Check the correct positon of the message in CHANGES.md file\n\n");
    $Self->Print(
        "Do you want to: <yellow>[C]</yellow>ommit, Commit and <yellow>[P]</yellow>ush or <yellow>[S]</yellow>top:"
    );

    my $Answer = <>;

    # Remove white space from input.
    $Answer =~ s{\s}{}smx;

    $Self->Print("\n");

    return 1 if $Answer =~ m{^s}ix;

    my $Message
        = $IsFrameworkTranslation ? '"" --allow-empty-message' : '"Updated translations, thanks to all translators."';

    @Tasks = (
        {
            Message => 'Committing Local translations (.pot and .pm files)',
            Command => "cd $TargetDirectory && git commit -am $Message --no-verify",
        },
    );

    if ( $Answer =~ m{^p}ix ) {
        push @Tasks, {
            Message => 'Pushing Local -> git (.pot and .pm files)',
            Command => "cd $TargetDirectory && git push",
        };
        push @Tasks, {
            Message => 'Pulling git -> Weblate (.pot file)',
            Command => "cd $TargetDirectory && $ClientPath pull",
        };
    }

    TASK:
    for my $Task (@Tasks) {
        my $Success = $Self->System( %{$Task} );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub UpdatePOFiles {
    my ( $Self, %Param ) = @_;

    my $ClientPath      = $Param{ClientPath};
    my $TargetDirectory = $Param{TargetDirectory};

    my @Tasks = (
        {
            Message => 'Locking Weblate translations',
            Command => "cd $TargetDirectory && $ClientPath lock",
        },
        {
            Message => 'Committing Weblate translations (.po files)',
            Command => "cd $TargetDirectory && $ClientPath commit",
        },
        {
            Message => 'Pushing Weblate -> git (.po files)',
            Command => "cd $TargetDirectory && $ClientPath push",
        },
        {
            Message => 'Pulling git -> Local (.po files)',
            Command => "cd $TargetDirectory && git pull",
        },
    );

    TASK:
    for my $Task (@Tasks) {
        my $Success = $Self->System( %{$Task} );
        if ( !$Success ) {
            return;
        }
    }

    $Self->Print("\nPlease review the .po files\n");
    $Self->Print("Manually run OTRS Code policy... \n\n");
    $Self->Print("Does any file was changed? <yellow>[Y]</yellow>es/<yellow>[N]o</yellow>:");

    my $Answer = <>;

    # Remove white space from input.
    $Answer =~ s{\s}{}smx;

    $Self->Print("\n");

    @Tasks = ();

    # Commit changes if user answers affirmatively.
    if ( $Answer =~ m{^y}ix ) {
        push @Tasks, {
            Message => 'Staging Local translations (.po files)',
            Command => "cd $TargetDirectory && git add i18n",
        };
        push @Tasks, {
            Message => 'Committing Local translations (.po files)',
            Command => "cd $TargetDirectory && git commit -am \"Fixed translation files.\" --no-verify",
        };
        push @Tasks, {
            Message => 'Pushing Local -> git (.po files)',
            Command => "cd $TargetDirectory && git push",
        };
        push @Tasks, {
            Message => 'Pulling git -> Weblate (.po files)',
            Command => "cd $TargetDirectory && $ClientPath pull",
        };
    }

    push @Tasks, {
        Message => 'Unlocking Weblate translations',
        Command => "cd $TargetDirectory && $ClientPath unlock",
    };

    TASK:
    for my $Task (@Tasks) {
        my $Success = $Self->System( %{$Task} );
        if ( !$Success ) {
            return;
        }
    }

    return 1;
}

sub System {
    my ( $Self, %Param ) = @_;

    $Self->Print("$Param{Message}... ");

    # Execute the command
    my $Error;
    my $Output;
    my $ReturnCode;
    my $CMDPID;
    my $EvalSuccess = eval {

        local $SIG{CHLD} = 'DEFAULT';

        # Localize the standard output and error, everything will be restored after the eval block.
        local ( *CMDIN, *CMDOUT, *CMDERR );    ## no critic (Variables::RequireInitializationForLocalVars)
        $CMDPID = open3( *CMDIN, *CMDOUT, *CMDERR, $Param{Command} );
        close CMDIN;

        waitpid( $CMDPID, 0 );

        # Redirect the standard output and error to a variable.
        my @Outlines = <CMDOUT>;
        my @Errlines = <CMDERR>;
        close CMDOUT;
        close CMDERR;

        $Output = join "", @Outlines;
        $Error  = join "", @Errlines;
        $Output //= '';
        $Error  //= '';

        $ReturnCode = $? >> 8;
        $ReturnCode //= 0;
    };

    # Check if command failed (e.g. not found) CMDPID is not populated.
    if ( !defined $CMDPID ) {
        $Self->Print("<red>Fail</red>\n");
        $Self->PrintError("    $Param{Command}: could not not be executed\n\n");
        return;
    }

    if ($Error) {
        $Error =~ s{^}{    }mgx;
    }
    if ($Output) {
        $Output =~ s{^}{    }mgx;
    }

    # Special case for git commit
    if ( $Output =~ m(Your[ ]branch[ ]is[ ]up[ ]to[ ]date[ ]with)msx && $ReturnCode == 1 ) {
        $ReturnCode = 0;
    }

    if ($ReturnCode) {
        $Self->Print("<red>Fail</red>\n\n");
        if ($Output) {
            $Self->Print("$Output\n");
        }
        if ($Error) {
            $Self->Print("<red>$Error</red>\n");
        }
        return;
    }

    $Self->Print("<green>OK</green>\n");
    if ( $Output && !$Param{Silent} ) {
        $Self->Print("$Output\n");
    }
    if ($Error) {
        $Self->Print("<yellow>$Error</yellow>\n");
    }

    return 1;
}

sub RunModule {
    my ( $Self, %Param ) = @_;

    # TODO: This function can be merged with System(), uses almost the same variables. and logic

    $Self->Print("$Param{Message}... ");

    my $ExitCode;
    my $Output;
    my $Error;
    {

        # Localize the standard error, everything will be restored after the block.
        local *STDERR;
        local *STDOUT;

        # Redirect the standard error and output to a variable.
        my $Success = open STDERR, ">>", \$Error;
        $Success = open STDOUT, ">>", \$Output;

        my $Module = $Param{Module}->new();
        $ExitCode = $Module->Execute( @{ $Param{Params} } );
    }

    $Output ||= '';
    $Error  ||= '';

    $Output =~ s{^}{  }mgx;
    $Output =~ s{Done.}{Done.\n}mgx;
    $Error  =~ s{^}{  }mgx;

    if ($ExitCode) {
        $Self->Print("<red>Fail</red>\n\n");
        if ($Output) {
            $Self->Print("$Output\n");
        }
        if ($Error) {
            $Self->Print("<red>$Error</red>\n");
        }
        return;
    }

    $Self->Print("<green>OK</green>\n");
    if ( $Output && !$Param{Silent} ) {
        $Self->Print("$Output\n");
    }
    if ($Error) {
        $Self->Print("<yellow>$Error</yellow>\n");
    }

    return 1;
}

sub FrameworkVersionGet {
    my ( $Self, %Param ) = @_;

    my $FH;

    my $Filename = $Param{FrameworkDirectory} . '/CHANGES.md';
    $Filename =~ s{//}{/}xmsg;

    my $Mode = '<:utf8';

    return if !open $FH, $Mode, $Filename;
    return if !flock $FH, LOCK_SH;

    my @FileLines = <$FH>;
    close $FH;

    # Get the last version with a date.
    my $Version;
    LINE:
    for my $Line (@FileLines) {
        ($Version) = $Line =~ m{\#(\d\.\d\.\d{2})[ ]\d{4}-\d{2}-\d{2}}msxi;
        last LINE if $Version;
    }
    return $Version;
}

1;
