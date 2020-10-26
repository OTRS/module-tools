# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

## nofilter(TidyAll::Plugin::OTRS::Perl::Require)

package Console::Command::TestSystem::Instance::Reset;

use strict;
use warnings;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . "/Kernel/cpan-lib";

# Also use relative path to find this if invoked inside of the OTRS directory.
use lib ".";
use lib "./Kernel/cpan-lib";
use lib dirname($RealBin) . '/Custom';

eval {
    require Kernel::Config;
};

use parent qw(Console::BaseCommand);

use Console::Command::Module::Package::Uninstall;
use Console::Command::TestSystem::Database::Install;
use Console::Command::TestSystem::Database::Fill;

=head1 NAME

Console::Command::TestSystem::Instance::Reset - Console command to reset an OTRS instance

=head1 SYNOPSIS

Resets an OTRS instance and fills it up with sample data (TestSystem::Database::Fill)

=cut

## nofilter(TidyAll::Plugin::OTRS::Perl::ObjectManagerCreation)
sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Reset an OTRS database and insert sample data (TestSystem::Database::Fill).');
    $Self->AddOption(
        Name        => 'framework-directory',
        Description => 'Specify a base framework directory.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'fill',
        Description => 'Specify if the OTRS database should be populated with sample data.',
        Required    => 0,
        HasValue    => 0,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    eval { require Kernel::Config };
    if ($@) {
        die "This console command needs to be run from a framework root directory!";
    }

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );

    if ( !-e $FrameworkDirectory ) {
        die "$FrameworkDirectory does not exist";
    }
    if ( !-d $FrameworkDirectory ) {
        die "$FrameworkDirectory is not a directory";
    }

    if ( !-e ( $FrameworkDirectory . '/RELEASE' ) ) {
        die "$FrameworkDirectory does not seem to be an OTRS framework directory";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );

    # Remove possible slash at the end.
    $FrameworkDirectory =~ s{ / \z }{}xms;

    $Self->Print("<yellow>Resetting OTRS instance...</yellow>\n");

    $Self->Print("<yellow>Do you really want to reset your OTRS instance? [Y]es/[N]o: </yellow>");
    my $Answer = <STDIN>;    ## no critic

    # Remove white space from input.
    $Answer =~ s{\s}{}smx;

    return $Self->ExitCodeOk() if $Answer !~ m{^y}i;

    $Self->Print("\n<yellow>Uninstalling all packages...</yellow>");
    my $Success = $Self->ExecuteCommand(
        Module => 'Console::Command::Module::Package::Uninstall',
        Params => [ '', $FrameworkDirectory, '--all' ],
    );

    if ( !$Success ) {
        $Self->PrintError("\nCould not uninstall all packages!\n");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<yellow>Resetting the database...</yellow>");
    $Success = $Self->ExecuteCommand(
        Module => 'Console::Command::TestSystem::Database::Install',
        Params => [ '--framework-directory', $FrameworkDirectory, '--delete' ],
    );

    if ( !$Success ) {
        $Self->PrintError("\nCould not reset the database!\n");
        return $Self->ExitCodeError();
    }

    if ( $Self->GetOption('fill') ) {
        $Self->Print("\n<yellow>Injecting some test data...</yellow>\n");

        my %Config = %{ $Self->{Config}->{TestSystem} || {} };

        # Get OTRS major version number.
        my $OTRSReleaseString = `cat $FrameworkDirectory/RELEASE`;
        my $OTRSMajorVersion  = '';
        if ( $OTRSReleaseString =~ m{ VERSION \s+ = \s+ (\d+) .* \z }xms ) {
            $OTRSMajorVersion = $1;
        }

        # Define some maintenance commands.
        if ( $OTRSMajorVersion >= 5 ) {
            $Config{RebuildConfigCommand}
                = "sudo -u $Config{PermissionsOTRSUser} $FrameworkDirectory/bin/otrs.Console.pl Maint::Config::Rebuild";
        }
        else {
            $Config{RebuildConfigCommand}
                = "sudo -u $Config{PermissionsOTRSUser} perl $FrameworkDirectory/bin/otrs.RebuildConfig.pl";
        }

        $Self->System( $Config{RebuildConfigCommand} );

        $Self->ExecuteCommand(
            Module => 'Console::Command::TestSystem::Database::Fill',
            Params => [ '--framework-directory', $FrameworkDirectory ],
        );
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub ExecuteCommand {
    my ( $Self, %Param ) = @_;

    my $Output;
    {

        # Localize the standard error, everything will be restored after the block.
        local *STDERR;
        local *STDOUT;

        # Redirect the standard error and output to a variable.
        open STDERR, ">>", \$Output;
        open STDOUT, ">>", \$Output;

        my $ModuleObject = $Param{Module}->new();

        # Allow running as root, if parent command has been allowed to do so.
        if ( $Self->{AllowRoot} ) {
            unshift @{ $Param{Params} }, '--allow-root';
        }

        $ModuleObject->Execute( @{ $Param{Params} } );
    }

    $Output =~ s{^}{    }mg;
    $Self->Print($Output);

    return 1;
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
