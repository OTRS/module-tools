# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package System;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec();

=head1 NAME

System - several helper functions

=head1 PUBLIC INTERFACE

=head2 GetHome()

gets the home directory of the provisioner.

    my $Home = System::GetHome();

=cut

sub GetHome {
    return dirname( dirname( File::Spec->rel2abs(__FILE__) ) );
}

=head2 ObjectInstanceCreate()

creates a new object instance

    my $Object = System::ObjectInstanceCreate(
        'My::Package',      # required
        ObjectParams => {   # optional, passed to constructor
            Param1 => 'Value1',
        },
        Silent => 1,        # optional (default 0) - disable exceptions
    );

Please note that this function might throw exceptions in case of error.

=cut

sub ObjectInstanceCreate {
    my ( $Package, %Param ) = @_;

    my $FileName = $Package;
    $FileName =~ s{::}{/}g;
    $FileName .= '.pm';
    my $RequireSuccess = eval {
        ## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
        require $FileName;
    };

    if ( !$RequireSuccess ) {
        if ( !$Param{Silent} ) {
            die "Could not require $Package:\n$@";
        }
        return;
    }

    my $Instance = $Package->new( @{ $Param{ObjectParams} // [] } );
    return $Instance if $Instance;

    if ( !$Param{Silent} ) {
        die "Could not instantiate $Package.";
    }
    return;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
