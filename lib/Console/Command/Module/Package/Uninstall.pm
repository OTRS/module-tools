# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Module::Package::Uninstall;

use strict;
use warnings;

use File::Spec ();

use Console::Command::Module::File::Unlink;
use Console::Command::Module::Database::Uninstall;
use Console::Command::Module::Code::Uninstall;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::Package::Uninstall - Console command to uninstall a module

=head1 DESCRIPTION

Run code uninstall, run database uninstall, and unlink a OTRS module from the framework.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Uninstall a module from framework root.');
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
    $Self->AddOption(
        Name        => 'verbose',
        Description => "Print detailed command output.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    my $Name = $Self->Name();

    $Self->AdditionalHelp(<<"EOF");

<yellow>Uninstalling from relative module directory</yellow>

    <green>otrs.ModuleTools.pl $Name ../MyModule ./</green>
    <green>otrs.ModuleTools.pl $Name MyModule OTRS-5_0</green>

<yellow>Uninstalling from absolute module directory</yellow>

    <green>otrs.ModuleTools.pl $Name /Users/MyUser/ws/MyModule</green>
    <green>otrs.ModuleTools.pl $Name /Users/MyUser/ws/MyModule /Users/MyUser/ws/OTRS-5_0</green>

<yellow>Uninstalling from module collaction</yellow>

    <green>otrs.ModuleTools.pl $Name ModuleCollection</green>
EOF

    return;
}

sub PreRun {
    my ($Self) = @_;

    eval { require Kernel::Config };
    if ($@) {
        die "This console command needs to be run from a framework root directory!";
    }

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

    if ( !-e ( $FrameworkDirectory . '/RELEASE' ) ) {
        die "$FrameworkDirectory does not seem to be an OTRS framework directory";
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
        @Directories = reverse @{ $Self->{Config}->{ModuleCollection}->{$Module} // [] };
    }

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetArgument('framework-directory') || '.' );

    # Get OTRS major version number.
    my $OTRSReleaseString = `cat $FrameworkDirectory/RELEASE`;
    my $OTRSMajorVersion  = '';
    if ( $OTRSReleaseString =~ m{ VERSION \s+ = \s+ (\d+) .* \z }xms ) {
        $OTRSMajorVersion = $1;
    }

    my %Config = %{ $Self->{Config}->{TestSystem} || {} };

    # Define some maintenance commands.
    if ( $OTRSMajorVersion >= 5 ) {

        my $CleanupPart = '--cleanup';
        if ( $OTRSMajorVersion == 5 ) {

            $CleanupPart .= '-user-config';
        }

        $Config{RebuildConfigCommand}
            = "sudo -u $Config{PermissionsOTRSUser} $FrameworkDirectory/bin/otrs.Console.pl Maint::Config::Rebuild $CleanupPart";
        $Config{DeleteCacheCommand}
            = "sudo -u $Config{PermissionsOTRSUser} $FrameworkDirectory/bin/otrs.Console.pl Maint::Cache::Delete";
    }
    else {
        $Config{RebuildConfigCommand}
            = "sudo -u $Config{PermissionsOTRSUser} perl $FrameworkDirectory/bin/otrs.RebuildConfig.pl";
        $Config{DeleteCacheCommand}
            = "sudo -u $Config{PermissionsOTRSUser} perl $FrameworkDirectory/bin/otrs.DeleteCache.pl";
    }

    my $GlobalFail;

    MODULEDIRECTORY:
    for my $ModuleDirectory (@Directories) {

        # Look if an sopm exists.
        my @SOPMs = glob "$ModuleDirectory/*.sopm";

        if ( !@SOPMs || !$SOPMs[0] ) {
            $Self->PrintError("Couldn't find the SOPM file in $ModuleDirectory");
            return $Self->ExitCodeError();
        }

        my $ModuleName = $SOPMs[0];
        $ModuleName =~ s{$ModuleDirectory/(.*)\.sopm}{$1}i;

        $Self->Print("<yellow>Uninstalling $ModuleName module...</yellow>\n\n");

        my %ExitCodes;
        my $Output;
        {

            # Localize the standard error, everything will be restored after the block.
            local *STDERR;
            local *STDOUT;

            # Redirect the standard error and output to a variable.
            open STDERR, ">>", \$Output;
            open STDOUT, ">>", \$Output;

            my $ModuleFilePath = $SOPMs[0];
            $ModuleFilePath =~ s{$ModuleDirectory/}{$FrameworkDirectory/};

            my $CodeModule = Console::Command::Module::Code::Uninstall->new();
            $ExitCodes{CodePre} = $CodeModule->Execute( $ModuleFilePath, 'pre' );

            my $DatabaseModule = Console::Command::Module::Database::Uninstall->new();
            $ExitCodes{DatabasePre} = $DatabaseModule->Execute( $ModuleFilePath, 'pre' );

            $ExitCodes{DatabasePost} = $DatabaseModule->Execute( $ModuleFilePath, 'post' );

            $ExitCodes{CodePost} = $CodeModule->Execute( $ModuleFilePath, 'post' );

            my $LinkModule = Console::Command::Module::File::Unlink->new();
            $ExitCodes{Files} = $LinkModule->Execute( $ModuleDirectory, $FrameworkDirectory );

            $Self->System( $Config{RebuildConfigCommand} );
            $Self->System( $Config{DeleteCacheCommand} );
        }

        if ( $Self->GetOption('verbose') ) {
            $Output =~ s{^}{  }mg;
            $Output =~ s{Done.}{Done.\n}mg;
            $Self->Print($Output);
        }

        my $Fail;
        EXITCODE:
        for my $ExitCode ( sort keys %ExitCodes ) {
            if ( $ExitCodes{$ExitCode} ) {
                $Fail = 1;
            }
            last EXITCODE;
        }

        if ($Fail) {
            $Self->PrintError("Could not uninstall $ModuleName module correctly!");
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

sub System {
    my ( $Self, $Command ) = @_;

    my $Output = `$Command`;

    if ($Output) {
        $Output =~ s{^}{    }mg;
        $Self->Print($Output);
    }

    return 1;
}

1;
