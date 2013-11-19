#!/usr/bin/perl
# --
# DatabaseInstall.pl - to install the packages DatabaseInstall()
# Copyright (C) 2001-2013 OTRS AG, http://otrs.com/
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

=head1 NAME

DatabaseInstall.pl - script to setup database tables of linked modules for development

=head1 SYNOPSIS

DatabaseInstall.pl -m MyModule.sopm -a [install|uninstall]

=head1 DESCRIPTION

Please send any questions, suggestions & complaints to <dev-support@otrs.com>

=cut

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . "/Kernel/cpan-lib";

use Getopt::Long;
use Pod::Usage;

use Kernel::Config;
use Kernel::System::Encode;
use Kernel::System::Log;
use Kernel::System::Main;
use Kernel::System::DB;
use Kernel::System::Time;
use Kernel::System::Package;

my ( $OptHelp, $Module, $Action );

GetOptions(
    'h'   => \$OptHelp,
    'm=s' => \$Module,
    'a=s' => \$Action
);

if ( $OptHelp || !$Module ) {
    pod2usage( -verbose => 0 );
}

if ( !defined $Action || $Action ne 'uninstall' ) {
    $Action = 'install';
}

# check if .sopm file exists
if ( !-e "$Module" ) {
    print "Can not find file $Module!\n";
    exit 0;
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
    Directory => '.',
    Filename  => $Module,
);

my %Structure = $CommonObject{PackageObject}->PackageParse( String => $PackageContent );

if ( $Action eq 'install' && $Structure{DatabaseInstall} ) {

    if ( $Structure{DatabaseInstall}->{pre} ) {
        $CommonObject{PackageObject}->_Database(
            Database => $Structure{DatabaseInstall}->{pre},
        );
    }

    if ( $Structure{DatabaseInstall}->{post} ) {
        $CommonObject{PackageObject}->_Database(
            Database => $Structure{DatabaseInstall}->{post},
        );
    }
}

if ( $Action eq 'uninstall' && $Structure{DatabaseUninstall} ) {
    if ( $Structure{DatabaseUninstall}->{pre} ) {
        $CommonObject{PackageObject}->_Database(
            Database => $Structure{DatabaseUninstall}->{pre},
        );
    }
    if ( $Structure{DatabaseUninstall}->{post} ) {
        $CommonObject{PackageObject}->_Database(
            Database => $Structure{DatabaseUninstall}->{post},
        );
    }
}

print "... done\n"
