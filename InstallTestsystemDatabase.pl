#!/usr/bin/perl
# --
# InstallTestsystemDatabase.pl - Execute XML on the database
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
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

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';
use lib dirname($RealBin) . '/Custom';

use Kernel::Config;
use Kernel::System::Encode;
use Kernel::System::Log;
use Kernel::System::Time;
use Kernel::System::Main;
use Kernel::System::DB;
use Kernel::System::XML;

local $Kernel::OM;
if ( eval 'require Kernel::System::ObjectManager' ) {    ## no critic

    # create object manager
    $Kernel::OM = Kernel::System::ObjectManager->new();
}

# create common objects
my %CommonObject = ();
$CommonObject{ConfigObject} = Kernel::Config->new(%CommonObject);
$CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
$CommonObject{LogObject}
    = Kernel::System::Log->new( %CommonObject, LogPrefix => 'OTRS-InstallTestsystemDatabase.pl' );
$CommonObject{TimeObject} = Kernel::System::Time->new(%CommonObject);
$CommonObject{MainObject} = Kernel::System::Main->new(%CommonObject);
$CommonObject{DBObject}   = Kernel::System::DB->new(%CommonObject);
$CommonObject{XMLObject}  = Kernel::System::XML->new(%CommonObject);

# install database
print STDERR "--- Creating tables and inserting data...\n";

my $InstallDir = $ARGV[0];

# create database tables and insert initial values
my @SQLPost;
for my $SchemaFile (qw ( otrs-schema otrs-initial_insert )) {

    my $Path = "$InstallDir/scripts/database/";

    if ( !-f $Path . $SchemaFile . '.xml' ) {
        print $Path . $SchemaFile . ".xml not found\n",
    }

    my $XML = $CommonObject{MainObject}->FileRead(
        Directory => $Path,
        Filename  => $SchemaFile . '.xml',
    );
    my @XMLArray = $CommonObject{XMLObject}->XMLParse(
        String => $XML,
    );

    my @SQL = $CommonObject{DBObject}->SQLProcessor(
        Database => \@XMLArray,
    );

    # if we parsed the schema, catch post instructions
    if ( $SchemaFile eq 'otrs-schema' ) {
        @SQLPost = $CommonObject{DBObject}->SQLProcessorPost();
    }

    for my $SQL (@SQL) {
        $CommonObject{DBObject}->Do( SQL => $SQL );
    }
}

# execute post SQL statements (indexes, constraints)
for my $SQL (@SQLPost) {
    $CommonObject{DBObject}->Do( SQL => $SQL );
}

1;
