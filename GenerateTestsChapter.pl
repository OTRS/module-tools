#!/usr/bin/perl
# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
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
use FindBin qw($RealBin $Script);
use lib $RealBin;
use lib $RealBin . '/Docbook/lib';

use vars (qw($Self @ISA));

eval { require XML::Simple };
if ($@) {
    print "Can't load XML::Simple: $@";
    exit 1;
}

use OTRS::XML::Simple;
use Getopt::Std;

use base qw(Docbook::Base);

my $Self = {};
bless( $Self, 'main' );

# get options
my %Opts = ();
getopt( 'hmofl', \%Opts );

if ( $Opts{h} ) {
    _Help();
    exit 1;
}

# check for module parameter
if ( !$Opts{m} ) {
    _Help();
    print "\n missing path to module\n";
    print "Example: $Script -m /Modules/MyModule\n";
    exit 1;
}

my %Options;

# set output file
my $OutputFile = $Opts{o} ? $Opts{o} . '.xml' : 'TestChapter.xml';

# cleanup module path
$Opts{m} =~ s{(.+)/\z}{$1}smx;

$Options{ModulePath}        = $Opts{m};
$Options{Language}          = $Opts{l} ? $Opts{l} : 'en';
$Options{UnitTestDirectory} = $Opts{m} . '/scripts/test';
$Options{OutputLocation}    = $Opts{m} . '/doc/' . $Options{Language} . '/' . $OutputFile;

# create parser in / out object
my $XMLObject = new OTRS::XML::Simple;    ##no critic

# output
print "+----------------------------------------------------------------------------+\n";
print "| Create tests chapter into to Docbook:\n";
print "| Module:    $Options{ModulePath}\n";
print "| From:      $Options{UnitTestDirectory}\n";
print "| To:        $Options{OutputLocation}\n";
print "+----------------------------------------------------------------------------+\n";

# get all unit test files from the package
my @UnitTestFiles = _GetUnitTestFiles(
    %Options,
);

# generate XML Docbook config chapter based in config file
my $Chapter = _CreateDocbookUnittestChapter(
    FileList => \@UnitTestFiles,
);
exit 1 if !$Chapter;

# write the XML file in the file system
my $WriteUnittestuccess = $Self->_WriteDocbookFile(
    Chapter   => $Chapter,
    XMLObject => $XMLObject,
    %Options,
);
exit 1 if !$WriteUnittestuccess;

# internal functions
sub _Help {
    my %Param = @_;

    print "$Script - Generate module tests chapter\n";
    print "Copyright (C) 2001-2016 OTRS AG, http://otrs.com/\n";
    print "usage: $Script -m <path to module> -l <language> (optional)"
        . " -o <Output filename> (optional)\n";

    exit 1;
}

sub _GetUnitTestFiles {
    my %Param = @_;

    # get all unit test from the module
    my @UnitTestFiles = $Self->_DirectoryRead(
        Directory => $Param{UnitTestDirectory},
        Filter    => '*.t',
        Recursive => 1,
    );

    if ( scalar @UnitTestFiles == 0 ) {
        print STDERR "No unit test found in $Opts{m}\n";
        exit 1;
    }

    return @UnitTestFiles;
}

sub _CreateDocbookUnittestChapter {
    my %Param = @_;

    # check needed parameters
    for my $Needed (qw(FileList)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    $Chapter = <<"XML";
<chapter>
    <title>Tests</title>
    <para>
        This module has been tested on the current state of the art in quality.
    </para>
    <section>
        <title>Test Cases</title>
        <para>
            To test this package please follow the examples described in the Usage section.
        </para>
    </section>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= '<!--'
    }

    $Chapter .= <<"XML";
    <section>
        <title>Unit Test</title>
        <para>
            To ensure the quality of the module, several so-called unit tests were created, to test
            the functionalities of this module. These unit tests can be run via command line.
        </para>
        <para>
            ATTENTION: Please never run unit tests on a productive system, since the added test
            data to the system will no longer be removed. Always use a test system.
        </para>
        <para>Run the package specific unit tests</para>
        <para>
            To run only the unit test which will be delivered with this package, use the following
            command on the command line:
        </para>
         <para>
            <screen>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= 'shell> perl bin/otrs.Console.pl Dev::UnitTest::Run - - test'
    }

    for my $File ( sort { "\L$a" cmp "\L$b" } @{ $Param{FileList} } ) {

        $File =~ s{./scripts/test/}{}msxi;
        $File =~ s{\.t\z}{}msxi;

        $Chapter .= "shell> perl bin/otrs.Console.pl Dev::UnitTest::Run --test $File\n";

        # output
        print "Added file: $File...done\n";
    }

    $Chapter .= <<"XML";
            </screen>
        </para>
        <para>
            Run all available unit tests
        </para>
        <para>
            To run all available unit tests, use the following command on the command line:
        </para>
        <para>
            <screen>
shell> perl bin/otrs.Console.pl Dev::UnitTest::Run
            </screen>
        </para>
    </section>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= "-->\n";
    }

    $Chapter .= '</chapter>';

    #output
    print "\nGenerating Docbook structure...";

    # output
    print "done\n";

    return $Chapter;
}

1;
