# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
## nofilter(TidyAll::Plugin::OTRS::Perl::ObjectDependencies)
## nofilter(TidyAll::Plugin::OTRS::Migrations::OTRS6::SysConfig)
## nofilter(TidyAll::Plugin::OTRS::Migrations::OTRS6::TimeObject)

package Console::Command::TestSystem::Database::Fill;

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
    require Kernel::System::Time;
    require Kernel::System::Log;
    require Kernel::System::Main;
    require Kernel::System::DB;
    require Kernel::System::SysConfig;
    require Kernel::System::User;
    require Kernel::System::Group;
    require Kernel::System::CustomerUser;
    require Kernel::System::CustomerCompany;
    require Kernel::System::Service;
    require Kernel::System::SLA;
    require Kernel::System::DynamicField;
};

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::TestSystem::Database::Fill - Console command to populate an OTRS database

=head1 SYNOPSIS

Adds users, customers, services and slas to an OTRS database

=cut

## nofilter(TidyAll::Plugin::OTRS::Perl::ObjectManagerCreation)
sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Populate an OTRS database with sample data.');
    $Self->AddOption(
        Name        => 'framework-directory',
        Description => "Specify a base framework directory.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
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
        die "$FrameworkDirectory does not seams to be an OTRS framework directory";
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
                LogPrefix => 'OTRS-TestSystem::Database::Fill',
            },
        );
    }

    my %CommonObject = ();
    if ($Kernel::OM) {
        $CommonObject{ConfigObject}          = $Kernel::OM->Get('Kernel::Config');
        $CommonObject{EncodeObject}          = $Kernel::OM->Get('Kernel::System::Encode');
        $CommonObject{LogObject}             = $Kernel::OM->Get('Kernel::System::Log');
        $CommonObject{TimeObject}            = $Kernel::OM->Get('Kernel::System::Time');
        $CommonObject{MainObject}            = $Kernel::OM->Get('Kernel::System::Main');
        $CommonObject{DBObject}              = $Kernel::OM->Get('Kernel::System::DB');
        $CommonObject{SysConfigObject}       = $Kernel::OM->Get('Kernel::System::SysConfig');
        $CommonObject{UserObject}            = $Kernel::OM->Get('Kernel::System::User');
        $CommonObject{GroupObject}           = $Kernel::OM->Get('Kernel::System::Group');
        $CommonObject{CustomerUserObject}    = $Kernel::OM->Get('Kernel::System::CustomerUser');
        $CommonObject{CustomerCompanyObject} = $Kernel::OM->Get('Kernel::System::CustomerCompany');
        $CommonObject{ServiceObject}         = $Kernel::OM->Get('Kernel::System::Service');
        $CommonObject{SLAObject}             = $Kernel::OM->Get('Kernel::System::SLA');
        $CommonObject{DynamicFieldObject}    = $Kernel::OM->Get('Kernel::System::DynamicField');
    }
    else {
        $CommonObject{ConfigObject} = Kernel::Config->new();
        $CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
        $CommonObject{LogObject}
            = Kernel::System::Log->new( %CommonObject, LogPrefix => 'OTRS-TestSystem::Database::Fill' );
        $CommonObject{TimeObject}            = Kernel::System::Time->new(%CommonObject);
        $CommonObject{MainObject}            = Kernel::System::Main->new(%CommonObject);
        $CommonObject{DBObject}              = Kernel::System::DB->new(%CommonObject);
        $CommonObject{SysConfigObject}       = Kernel::System::SysConfig->new(%CommonObject);
        $CommonObject{UserObject}            = Kernel::System::User->new(%CommonObject);
        $CommonObject{GroupObject}           = Kernel::System::Group->new(%CommonObject);
        $CommonObject{CustomerUserObject}    = Kernel::System::CustomerUser->new(%CommonObject);
        $CommonObject{CustomerCompanyObject} = Kernel::System::CustomerCompany->new(%CommonObject);
        $CommonObject{ServiceObject}         = Kernel::System::Service->new(%CommonObject);
        $CommonObject{SLAObject}             = Kernel::System::SLA->new(%CommonObject);
        $CommonObject{DynamicFieldObject}    = Kernel::System::DynamicField->new(%CommonObject);
    }

    my %Config = %{ $Self->{Config}->{TestSystem} || {} };

    $Self->Print("<yellow>Inserting sample data...</yellow>\n");

    # Add Agents.
    AGENT:
    for my $Agent ( @{ $Config{Agents} } ) {

        next AGENT if !$Agent;
        next AGENT if !%{$Agent};

        # Check if this user already exists.
        my %User = $CommonObject{UserObject}->GetUserData(
            User => $Agent->{UserLogin},
        );
        if ( $User{UserID} ) {
            $Self->Print("  Agent <red>$Agent->{UserLogin}</red> already exists. Continue...\n");
            next AGENT;
        }

        my $UserID = $CommonObject{UserObject}->UserAdd(
            %{$Agent},
            ValidID      => 1,
            ChangeUserID => 1,
        );

        if ($UserID) {
            for my $GroupID (qw(1 2 3)) {
                if ( $CommonObject{GroupObject}->can('GroupMemberAdd') ) {
                    my $Success = $CommonObject{GroupObject}->GroupMemberAdd(
                        GID        => $GroupID,
                        UID        => $UserID,
                        Permission => {
                            rw => 1,
                        },
                        UserID => 1,
                    );
                }
                if ( $CommonObject{GroupObject}->can('PermissionGroupUserAdd') ) {
                    my $Success = $CommonObject{GroupObject}->PermissionGroupUserAdd(
                        GID        => $GroupID,
                        UID        => $UserID,
                        Permission => {
                            ro        => 1,
                            move_into => 1,
                            create    => 1,
                            owner     => 1,
                            priority  => 1,
                            rw        => 1,
                        },
                        UserID => 1,
                    );
                }
            }

            # Agent preferences.
            if ( $Agent->{UserPreferences} && $CommonObject{UserObject}->can('SetPreferences') ) {

                for my $Preference ( @{ $Agent->{UserPreferences} } ) {

                    $CommonObject{UserObject}->SetPreferences(
                        Key    => $Preference->{Key},
                        Value  => $Preference->{Value},
                        UserID => $UserID,
                    );
                }
            }

            $Self->Print("  Agent <yellow>$UserID</yellow> has been created.\n");
        }
    }

    # Add Customer Companies.
    CUSTOMERCOMPANY:
    for my $CustomerCompany ( @{ $Config{CustomerCompanies} } ) {

        next CUSTOMERCOMPANY if !$CustomerCompany;
        next CUSTOMERCOMPANY if !%{$CustomerCompany};

        # Check if this customer company already exists.
        my %CustomerCompanyData = $CommonObject{CustomerCompanyObject}->CustomerCompanyGet(
            CustomerID => $CustomerCompany->{CustomerID},
        );
        if ( $CustomerCompanyData{CustomerID} ) {
            $Self->Print("  Customer company <red>$CustomerCompany->{CustomerID}</red> already exists. Continue...\n");
            next CUSTOMERCOMPANY;
        }

        my $ID = $CommonObject{CustomerCompanyObject}->CustomerCompanyAdd(
            %{$CustomerCompany},
            Source  => 'CustomerCompany',
            ValidID => 1,
            UserID  => 1,
        );

        if ($ID) {
            $Self->Print("  Customer company $ID has been created.\n");
        }
    }

    # Add Customers.
    CUSTOMER:
    for my $Customer ( @{ $Config{Customers} } ) {

        next CUSTOMER if !$Customer;
        next CUSTOMER if !%{$Customer};

        # Check if this user already exists.
        my %User = $CommonObject{CustomerUserObject}->CustomerUserDataGet(
            User => $Customer->{UserLogin},
        );
        if ( $User{UserID} ) {
            $Self->Print("  Customer <red>$Customer->{UserLogin}</red> already exists. Continue...\n");
            next CUSTOMER;
        }

        my $UserID = $CommonObject{CustomerUserObject}->CustomerUserAdd(
            %{$Customer},
            Source  => 'CustomerUser',
            ValidID => 1,
            UserID  => 1,
        );

        if ($UserID) {
            $Self->Print("  Customer $UserID has been created.\n");
        }
    }

    # Deploy system configuration (< OTRS6).
    if ( $CommonObject{SysConfigObject}->can('WriteDefault') ) {
        $CommonObject{SysConfigObject}->WriteDefault();

        # Define the ZZZ files.
        my @ZZZFiles = (
            'ZZZAAuto.pm',
            'ZZZAuto.pm',
        );

        # Reload the ZZZ files (mod_perl workaround).
        for my $ZZZFile (@ZZZFiles) {
            PREFIX:
            for my $Prefix (@INC) {
                my $File = $Prefix . '/Kernel/Config/Files/' . $ZZZFile;
                next PREFIX if !-f $File;
                do $File;
                last PREFIX;
            }
        }
    }

    # Deploy system configuration (>= OTRS6).
    elsif ( $CommonObject{SysConfigObject}->can('ConfigurationDeploy') ) {

        $CommonObject{SysConfigObject}->ConfigurationDeploy(
            Comments    => 'Deployed by TestSystem::Database::Fill.',
            AllSettings => 1,
            UserID      => 1,
            Force       => 1,
        );

        # Remove the ZZZAAuto.pm from %INC to force reloading it.
        delete $INC{'Kernel/Config/Files/ZZZAAuto.pm'};
    }

    # Enable service (< OTRS 6).
    if ( $CommonObject{SysConfigObject}->can('SettingsSet') ) {
        $CommonObject{SysConfigObject}->SettingsSet(
            Settings => [
                {
                    Name           => 'Ticket::Service',
                    IsValid        => 1,
                    EffectiveValue => 1,
                },
            ],
            UserID => 1,
        );
    }

    # Enable service (>= OTRS 6).
    elsif ( $CommonObject{SysConfigObject}->can('ConfigItemUpdate') ) {
        $CommonObject{SysConfigObject}->ConfigItemUpdate(
            Valid => 1,
            Key   => 'Ticket::Service',
            Value => 1,
        );
    }

    # Add Services.
    my %ServicesNameToID;
    SERVICE:
    for my $Service ( @{ $Config{Services} } ) {

        next SERVICE if !$Service;
        next SERVICE if !%{$Service};

        # Check if this service already exists.
        my $ExistingServiceID = $CommonObject{ServiceObject}->ServiceLookup(
            Name => $Service->{Name},
        );

        if ($ExistingServiceID) {
            $Self->Print("  Service <red>$Service->{Name}</red> already exists. Continue...\n");
            next SERVICE;
        }

        my $ServiceID = $CommonObject{ServiceObject}->ServiceAdd(
            %{$Service},
            ValidID => 1,
            UserID  => 1,
        );

        if ($ServiceID) {
            $Self->Print("  Service <yellow>$ServiceID</yellow> has been created.\n");
            $ServicesNameToID{ $Service->{Name} } = $ServiceID;
        }

        # Add service as default service for all customers.
        $CommonObject{ServiceObject}->CustomerUserServiceMemberAdd(
            CustomerUserLogin => '<DEFAULT>',
            ServiceID         => $ServiceID,
            Active            => 1,
            UserID            => 1,
        );
    }

    # Add SLAs and connect them with the Services.
    SLA:
    for my $SLA ( @{ $Config{SLAs} } ) {

        next SLA if !$SLA;
        next SLA if !%{$SLA};

        # Check if this SLA already exists.
        my $ExistingSLAID = $CommonObject{SLAObject}->SLALookup(
            Name => $SLA->{Name},
        );

        if ($ExistingSLAID) {
            $Self->Print("  SLA <red>$SLA->{Name}</red> already exists. Continue...\n");
            next SLA;
        }

        # Get Services that this SLA should be connected with.
        my @ServiceIDs;
        for my $Service ( sort keys %ServicesNameToID ) {
            if ( grep { $_ eq $Service } @{ $SLA->{ServiceNames} } ) {
                push @ServiceIDs, $ServicesNameToID{$Service};
            }
        }
        delete $SLA->{ServiceNames};

        my $SLAID = $CommonObject{SLAObject}->SLAAdd(
            %{$SLA},
            ServiceIDs => \@ServiceIDs,
            ValidID    => 1,
            UserID     => 1,
        );

        if ($SLAID) {
            $Self->Print("  SLA <yellow>$SLAID</yellow> has been created.\n");
        }
    }

    # Adding configured dynamic fields.
    if ( @{ $Config{DynamicFields} } ) {

        DYNAMICFIELD:
        for my $DynamicField ( reverse @{ $Config{DynamicFields} } ) {

            next DYNAMICFIELD if !$DynamicField;
            next DYNAMICFIELD if !$DynamicField;

            # Check if this dynamic field already exists.
            if ( $CommonObject{DynamicFieldObject}->can('DynamicFieldGet') ) {

                my $DynamicFieldData = $CommonObject{DynamicFieldObject}->DynamicFieldGet(
                    Name => $DynamicField->{Name},
                );

                if ( $DynamicFieldData->{ID} ) {
                    $Self->Print("  Dynamic Field <red>$DynamicField->{Name}</red> already exists. Continue...\n");
                    next DYNAMICFIELD;
                }
            }
            else {

                my $Field = $CommonObject{DynamicFieldObject}->FieldGet(
                    Name => $DynamicField->{Name},
                );

                if ( $Field && $Field->ID() ) {
                    $Self->Print("  Dynamic Field <red>$DynamicField->{Name}</red> already exists. Continue...\n");
                    next DYNAMICFIELD;
                }
            }

            # adding the dynamic field
            if ( $CommonObject{DynamicFieldObject}->can('DynamicFieldAdd') ) {

                my $ID = $CommonObject{DynamicFieldObject}->DynamicFieldAdd(
                    %{$DynamicField},
                    Reorder => 1,
                    ValidID => 1,
                    UserID  => 1,
                );

                if ($ID) {
                    $Self->Print("  Dynamic Field $ID has been created.\n");
                }
            }
            else {

                my $Field = $CommonObject{DynamicFieldObject}->FieldAdd(
                    %{$DynamicField},
                    Reorder => 1,
                    ValidID => 1,
                    UserID  => 1,
                );

                my $ID = $Field->ID();

                if ($ID) {
                    $Self->Print("  Dynamic Field $ID has been created.\n");
                }
            }
        }
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
