#!/usr/bin/perl
# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
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
my $OutputFile = $Opts{o} ? $Opts{o} . '.xml' : 'TechChapter.xml';

$Options{ModulePath}     = $Opts{m};
$Options{Language}       = $Opts{l} ? $Opts{l} : 'en';
$Options{OutputLocation} = $Opts{m} . '/doc/' . $Options{Language} . '/' . $OutputFile;
$Options{FrameworkPath}  = $Opts{f} ? $Opts{f} : '';

# create parser in / out object
my $XMLObject = OTRS::XML::Simple->new();

# output
print "+----------------------------------------------------------------------------+\n";
print "| Create Technical Implementation file list into to Docbook:\n";
print "| Module:    $Options{ModulePath}\n";
print "| From:      $Options{ModulePath}\n";
print "| To:        $Options{OutputLocation}\n";
if ( $Options{FrameworkPath} ) {
    print "| Framework: $Options{FrameworkPath}\n";
}
print "+----------------------------------------------------------------------------+\n";

# actual package files
my @PackageFiles = _GetPackageFiles(
    %Options,
);

# generate XML Docbook config chapter based in config file
my $Chapter = _CreateDocbookTechChapter(
    FileList => \@PackageFiles,
    %Options,
);
exit 1 if !$Chapter;

# write the XML file in the file system
my $WriteFileSuccess = $Self->_WriteDocbookFile(
    Chapter   => $Chapter,
    XMLObject => $XMLObject,
    %Options,
);
exit 1 if !$WriteFileSuccess;

# internal functions
sub _Help {
    my %Param = @_;

    print "$Script - Generate module technical implementation chapter\n";
    print "Copyright (C) 2001-2017 OTRS AG, http://otrs.com/\n";
    print "usage: $Script -m <path to module> -l <language> (optional)"
        . " -o <Output filename> (optional) -f <path to reference framework> (optional)\n";

    exit 1;
}

sub _GetPackageFiles {
    my %Param = @_;

    # get all files from the module
    my @FilesInDirectory = $Self->_DirectoryRead(
        Directory => $Param{ModulePath},
        Filter    => '*',
        Recursive => 1,
    );

    if ( scalar @FilesInDirectory == 0 ) {
        print STDERR "No files found in $Param{ModulePath}\n";
        exit 1;
    }

    FILE:
    for my $File (@FilesInDirectory) {

        next FILE if -d $File;
        next FILE if $File =~ m{/doc}msi;
        next FILE if $File =~ m{/development}msi;

        # clean file name
        $File =~ s{$Param{ModulePath}/}{};

        if ( $File =~ m{(.*)\.sopm}msi ) {
            my $ModuleName = $1;

            # check if SOPM can be found in the given framework
            if ( $Param{FrameworkPath} && -e "$Param{FrameworkPath}$File" ) {
                print STDERR "The package '$ModuleName' should not be linked into the framework!\n";
                exit 1;
            }

            next FILE;
        }

        push @PackageFiles, $File;
    }

    return @PackageFiles;
}

sub _CreateDocbookTechChapter {
    my %Param = @_;

    # check needed parameters
    for my $Needed (qw(FileList)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    # set basic structure
    my %Docbook = (
        chapter => {
            title   => 'Technical Implementation Details',
            section => [],
        },
    );

    my @ProcessedFiles;

    for my $File ( sort { "\L$a" cmp "\L$b" } @{ $Param{FileList} } ) {

        my $DescriptionContent = _GetDecription($File);

        my $Type = 'New';
        if ( $File =~ m{\ACustom}msi ) {
            $Type = 'Change';
        }
        elsif ( $Param{FrameworkPath} && -e "$Param{FrameworkPath}$File" ) {
            $Type = 'Change';
        }

        push @ProcessedFiles, {
            title => "$File.",
            para  => [
                "$Type: $DescriptionContent",
            ],
        };

        # output
        print "Added file: $File...done\n";
    }

    $Docbook{chapter}->{section} = \@ProcessedFiles;

    #output
    print "\nGenerating Docbook structure...";

    # convert perl structure into XML structure
    my $Chapter = eval {
        $XMLObject->XMLout(
            \%Docbook,
            NoAttr   => 1,
            KeepRoot => 1
        );
    };

    if ($@) {
        print "\nThere was an error adding files into XML: $@\n";
        return;
    }

    # indentation = 4 spaces
    my $Indentation = '    ';
    $Chapter =~ s{[ ]{2}}{$Indentation}gmx;

    # output
    print "done\n";

    return $Chapter;
}

sub _GetDecription {
    my $File = shift;

    my %DefaultUsedLanguages = (
        'ar_SA'   => 'Arabic (Saudi Arabia)',
        'bg'      => 'Bulgarian',
        'ca'      => 'Catalan',
        'cs'      => 'Czech',
        'da'      => 'Danish',
        'de'      => 'German',
        'en'      => 'English (United States)',
        'en_CA'   => 'English (Canada)',
        'en_GB'   => 'English (United Kingdom)',
        'es'      => 'Spanish',
        'es_CO'   => 'Spanish (Colombia)',
        'es_MX'   => 'Spanish (Mexico)',
        'et'      => 'Estonian',
        'el'      => 'Greek',
        'fa'      => 'Persian',
        'fi'      => 'Finnish',
        'fr'      => 'French',
        'fr_CA'   => 'French (Canada)',
        'gl'      => 'Galician',
        'he'      => 'Hebrew',
        'hi'      => 'Hindi',
        'hr'      => 'Croatian',
        'hu'      => 'Hungarian',
        'it'      => 'Italian',
        'ja'      => 'Japanese',
        'lt'      => 'Lithuanian',
        'lv'      => 'Latvian',
        'ms'      => 'Malay',
        'nl'      => 'Nederlands',
        'nb_NO'   => 'Norwegian',
        'pt_BR'   => 'Portuguese (Brasil)',
        'pt'      => 'Portuguese',
        'pl'      => 'Polish',
        'ru'      => 'Russian',
        'sl'      => 'Slovenian',
        'sr_Latn' => 'Serbian Latin',
        'sr_Cyrl' => 'Serbian Cyrillic',
        'sk_SK'   => 'Slovak',
        'sv'      => 'Swedish',
        'sw'      => 'Swahili',
        'tr'      => 'Turkish',
        'uk'      => 'Ukrainian',
        'vi_VN'   => 'Vietnam',
        'zh_CN'   => 'Chinese (Simplified)',
        'zh_TW'   => 'Chinese (Traditional)',
    );

    my %DefaultDescriptions = (
        'Kernel/Config/Files' =>
            'Configuration file that holds the required settings for the correct functionality of this package.',
        'Kernel/GenericInterface/Invoker'      => 'Generic interface invoker module that...',
        'Kernel/GenericInterface/Mapping'      => 'Generic interface mapping module that...',
        'Kernel/GenericInterface/Operation'    => 'Generic interface operation module that...',
        'Kernel/GenericInterface/Transport'    => 'Generic interface transport module that...',
        'Kernel/Modules'                       => 'Front-end module',
        'Kernel/Output/HTML/FilterElementPost' => 'Output filter that ...',
        'Kernel/Output/HTML/NavBar'            => 'Navigation bar module that ...',
        'Kernel/Output/HTML/Layout'            => 'Layout module that ...',
        'Kernel/Output/HTML/Templates'         => 'HTML template file for ...',
        'Kernel/Output/HTML/Preferences'       => 'Preferences module that ...',
        'Kernel/Output/HTML/Toolbar'           => 'Tool bard module for ...',
        'Kernel/System/'                       => 'Core module ...',
        'Kernel/System/Console/Command'        => 'Console command ...',
        'Kernel/System/PostMaster'             => 'Postmaster module that ...',
        'Kernel/System/Stats/Dynamic/'         => 'Dynamic statistic module that...',
        'Kernel/System/Stats/Static/'          => 'Static statistic module that...',
        'Kernel/System/Ticket'                 => 'Ticket module that redefines ...',
        'Kernel/System/Ticket/Acl/'            => 'Ticket ACL module that ...',
        'scripts/test'                         => 'Test file for ...',
        'skins/Agent'                          => 'Agent css file to ...',
        'skins/Customer'                       => 'Customer css file to ...',
        'var/packagesetup/'                    => 'Package helper to perform code operations during package setup.',
        'var/httpd/htdocs/js'                  => 'JavaScript file that ...',
        'var/stats/'                           => 'Statistics template for ...',
    );

    my $DescriptionContent = '...';

    # if the file is a language module
    if ( $File =~ m{Kernel/Language}msi ) {

        my $LanguageCode;

        # get language code from the language file e.g. 'en' from 'Kernel/Language/en_MyModule'
        if ( $File =~ m{Kernel/Language/(.*)_.*\.pm} ) {
            $LanguageCode = $1 // '';
        }

        $DescriptionContent = 'Translation file for this package.';

        # add specific description if language was found
        if ( $LanguageCode && $DefaultUsedLanguages{$LanguageCode} ) {
            $DescriptionContent = "$DefaultUsedLanguages{$LanguageCode} translation file for this package."
        }
    }
    else {

        # check if its an event module
        if ( $File =~ m{Kernel/System/(\w+)/Event}i ) {
            $DescriptionContent = "$1 event module to...";
        }
        else {

            # otherwise, check the default descriptions  based on the directory from bottom to up
            #   (to get more specific directories first, rather than general)
            DESCRIPTION:
            for my $Description ( sort { $b cmp $a } keys %DefaultDescriptions ) {
                if ( $File =~ m{$Description}i ) {
                    $DescriptionContent = $DefaultDescriptions{$Description};
                    last DESCRIPTION;
                }
            }
        }

        # if the file is in custom folder then prefix 'Customized' to the default description
        if ( $File =~ m {Custom/} ) {
            $DescriptionContent = $DescriptionContent ? 'Customized ' . lc $DescriptionContent : 'Customized file ...';
        }
    }

    return $DescriptionContent;
}

1;
