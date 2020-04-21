# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
## nofilter(TidyAll::Plugin::OTRS::Perl::ObjectDependencies)

package Console::Command::TestSystem::Database::Install;

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
    require Kernel::System::Encode;
    require Kernel::System::Log;
    require Kernel::System::Time;
    require Kernel::System::Main;
    require Kernel::System::DB;
    require Kernel::System::XML;
};

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::TestSystem::Database::Install - Console command to install an OTRS database

=head1 DESCRIPTION

Creates schema and initial data of an OTRS database

=cut

## nofilter(TidyAll::Plugin::OTRS::Perl::ObjectManagerCreation)
sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Creates tables and initial data into an OTRS database.');
    $Self->AddOption(
        Name        => 'framework-directory',
        Description => "Specify a base framework directory.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name => 'delete',
        Description =>
            "Delete existing tables before creation (removes old data). Note: removes only to standard OTRS Free tables.",
        Required => 0,
        HasValue => 0,
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

    if ( !-e $FrameworkDirectory . '/RELEASE' ) {
        die "$FrameworkDirectory does not seem to be an OTRS framework directory";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );

    # Remove possible slash at the end.
    $FrameworkDirectory =~ s{ / \z }{}xms;

    local $Kernel::OM;
    if ( eval 'require Kernel::System::ObjectManager' ) {    ## no critic

        # Create object manager.
        $Kernel::OM = Kernel::System::ObjectManager->new(
            'Kernel::System::Log' => {
                LogPrefix => 'OTRS-TestSystem::Database::Install',
            },
        );
    }

    # Create common objects.
    my %CommonObject = ();
    if ($Kernel::OM) {
        $CommonObject{ConfigObject} = $Kernel::OM->Get('Kernel::Config');
        $CommonObject{EncodeObject} = $Kernel::OM->Get('Kernel::System::Encode');
        $CommonObject{LogObject}    = $Kernel::OM->Get('Kernel::System::Log');
        $CommonObject{MainObject}   = $Kernel::OM->Get('Kernel::System::Main');
        $CommonObject{DBObject}     = $Kernel::OM->Get('Kernel::System::DB');
        $CommonObject{XMLObject}    = $Kernel::OM->Get('Kernel::System::XML');
    }
    else {
        $CommonObject{ConfigObject} = Kernel::Config->new(%CommonObject);
        $CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
        $CommonObject{LogObject}
            = Kernel::System::Log->new( %CommonObject, LogPrefix => 'OTRS-TestSystem::Database::Install' );
        $CommonObject{MainObject} = Kernel::System::Main->new(%CommonObject);
        $CommonObject{DBObject}   = Kernel::System::DB->new(%CommonObject);
        $CommonObject{XMLObject}  = Kernel::System::XML->new(%CommonObject);
    }

    # Install database.
    $Self->Print("<yellow>Creating tables and inserting data...</yellow>\n");

    # Create database tables and insert initial values.
    my @SQLPost;
    for my $SchemaFile (qw ( otrs-schema otrs-initial_insert )) {

        my $Path = "$FrameworkDirectory/scripts/database/";

        if ( !-f $Path . $SchemaFile . '.xml' ) {
            $Self->PrintError( $Path . $SchemaFile . ".xml not found!\n" );
        }

        my $XML = $CommonObject{MainObject}->FileRead(
            Directory => $Path,
            Filename  => $SchemaFile . '.xml',
        );
        my @XMLArray = $CommonObject{XMLObject}->XMLParse(
            String => $XML,
        );

        # Remove tables if requested.
        if ( $Self->GetOption('delete') && $SchemaFile eq 'otrs-schema' ) {
            $Self->Print("<yellow>Attempting to remove existing tables first...</yellow>\n");

            my @TablesToDrop;
            ARRAYKEY:
            for my $ArrayKey (@XMLArray) {
                next ARRAYKEY if $ArrayKey->{Tag} ne 'Table' && $ArrayKey->{Tag} ne 'TableCreate';
                next ARRAYKEY if $ArrayKey->{TagType} ne 'Start';

                push @TablesToDrop, $ArrayKey->{Name};
            }
            if (@TablesToDrop) {
                my $TableList = join ', ', @TablesToDrop;
                my $DBType    = $CommonObject{DBObject}->{'DB::Type'};

                if ( $DBType eq 'mysql' ) {

                    # Drop all tables in same statement.
                    $CommonObject{DBObject}->Do(
                        SQL =>
                            "SET FOREIGN_KEY_CHECKS = 0; DROP TABLE IF EXISTS $TableList; SET FOREIGN_KEY_CHECKS = 1",
                    );
                }
                elsif ( $DBType eq 'postgresql' ) {

                    # Drop all tables in same statement.
                    $CommonObject{DBObject}->Do( SQL => "DROP TABLE IF EXISTS $TableList CASCADE" );
                }
                elsif ( $DBType eq 'oracle' ) {

                    # Drop every table in a separate statement.
                    for my $Table (@TablesToDrop) {
                        $CommonObject{DBObject}->Do( SQL => "DROP TABLE $Table CASCADE CONSTRAINTS" );
                    }
                }
            }
        }

        my @SQL = $CommonObject{DBObject}->SQLProcessor(
            Database => \@XMLArray,
        );

        # If we parsed the schema, catch post instructions.
        if ( $SchemaFile eq 'otrs-schema' ) {
            @SQLPost = $CommonObject{DBObject}->SQLProcessorPost();
        }

        for my $SQL (@SQL) {
            $CommonObject{DBObject}->Do( SQL => $SQL );
        }

    }

    # Execute post SQL statements (indexes, constraints).
    for my $SQL (@SQLPost) {
        $CommonObject{DBObject}->Do( SQL => $SQL );
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
