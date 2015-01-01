#!/usr/bin/perl
# --
# ModuleCode.pl - to install the packagesetup CodeInstall()
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . "/Kernel/cpan-lib";

use Getopt::Std;

use Kernel::Config;
use Kernel::System::Encode;
use Kernel::System::Log;
use Kernel::System::Main;
use Kernel::System::DB;
use Kernel::System::Time;
use Kernel::System::Package;

# get options
my %Opt;
getopt( 'h', \%Opt );

if ( exists $Opt{h} || !$ARGV[1] ) {
    Usage();
    exit;
}

# call the script with the action as first argument
my $UserAction = shift;
my $Action;

POSSIBLEACTION:
for my $PossibleAction (qw(Install Reinstall Upgrade Uninstall)) {
    if ( $UserAction =~ m{\A \Q$PossibleAction\E \z}msxi ) {

        # change to correct case
        $Action = ucfirst( lc $UserAction );

        #add Code Prefix
        $Action = 'Code' . $Action;
        last POSSIBLEACTION;
    }
}

if ( !$Action ) {
    print "Action '$UserAction' is invalid!\n";
    Usage();
    exit 0;
}

# call the script with the module name as second argument
my $Module = shift;
if ( !-e $Module ) {
    print "Can not find file $Module!\n";
    exit 0;
}

# call the script with the type as the third argument (if any)
my $UserType = shift;
my $Type;

if ($UserType) {
    TYPE:
    for my $PossibleType (qw(post pre)) {

        if ( $UserType =~ m{\A \Q$PossibleType\E \z}msxi ) {

            # change to correct case
            $Type = lc $UserType;
            last TYPE;
        }
    }
    if ( !$Type ) {
        print "Type '$UserType' is invalid!\n";
        Usage();
        exit 0;
    }
}

# otherwise set default type
else {
    $Type = 'post';
    if ( $Action =~ m{\A CodeUninstall }msx ) {
        $Type = 'pre';
    }
}

# create common objects
my %CommonObject = ();
$CommonObject{ConfigObject} = Kernel::Config->new();
$CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
$CommonObject{LogObject}    = Kernel::System::Log->new(
    LogPrefix    => "OTRS-$Module",
    ConfigObject => $CommonObject{ConfigObject},
);
$CommonObject{MainObject}    = Kernel::System::Main->new(%CommonObject);
$CommonObject{DBObject}      = Kernel::System::DB->new(%CommonObject);
$CommonObject{TimeObject}    = Kernel::System::Time->new(%CommonObject);
$CommonObject{XMLObject}     = Kernel::System::XML->new(%CommonObject);
$CommonObject{PackageObject} = Kernel::System::Package->new(%CommonObject);

my $PackageContent = $CommonObject{MainObject}->FileRead(
    Location => $Module,
);

my %Structure = $CommonObject{PackageObject}->PackageParse( String => $PackageContent );

if ( $Structure{$Action} ) {
    $CommonObject{PackageObject}->_Code(
        Code      => $Structure{$Action},
        Type      => $Type,
        Structure => \%Structure,
    );
}

print "... done\n";

# exit after printing the usage message
sub Usage {
    my ($Message) = @_;

    $Message ||= '';

    print <<"END_OF_HERE";

$Message

USAGE:
    ModuleCode.pl <Action> <Path to linked .sopm file> <Type> (optional)
        Action (Install | ReInstall | Upgrade | Uninstall)
        Type (post | pre)

EXAMPLES:
    ModuleCode.pl Install ../FAQ.sopm post
    ModuleCode.pl Uninstall ../FAQ.sopm

END_OF_HERE

    exit 1;
}
