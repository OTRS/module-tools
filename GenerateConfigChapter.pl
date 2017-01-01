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
getopt( 'hmols', \%Opts );

if ( $Opts{h} ) {
    $Self->_Help();
    exit 1;
}

# check for module parameter
if ( !$Opts{m} ) {
    $Self->_Help();
    print "\n missing path to module\n";
    print "Example: $Script -m /Modules/MyModule\n";
    exit 1;
}

my %Options;

# set output file
my $OutputFile = $Opts{o} ? $Opts{o} . '.xml' : 'ConfigChapter.xml';

# cleanup module path
$Opts{m} =~ s{(.+)/\z}{$1}smx;

$Options{Language} = $Self->_GetLanguage(
    Language => $Opts{l} || '',
    ModulePath => $Opts{m},
);

$Options{ModulePath}      = $Opts{m};
$Options{ConfigDirectory} = $Opts{m} . '/Kernel/Config/Files';
$Options{OutputLocation}  = $Opts{m} . '/doc/' . $Options{Language} . '/' . $OutputFile;
$Options{SortByName}      = $Opts{s} // 1;

# output
print "+----------------------------------------------------------------------------+\n";
print "| Generating configuration chapter:\n";
print "| Module: $Options{ModulePath}\n";
print "| From:   $Options{ConfigDirectory}\n";
print "| To:     $Options{OutputLocation}\n";
print "+----------------------------------------------------------------------------+\n";

#  create parser in / out object
my $XMLObject = OTRS::XML::Simple->new();

# get all config settings from all files
my %ConfigSettings = $Self->_GetConfigSettings(
    %Options,
);

# generate XML Docbook config chapter based in config file
my $ConfigChapter = $Self->_CreateDocbookConfigChapter(
    ConfigSettings => \%ConfigSettings,
    %Options,
);
exit 1 if !$ConfigChapter;

# write the XML file in the file system
my $WriteFileSuccess = $Self->_WriteDocbookFile(
    Chapter   => $ConfigChapter,
    XMLObject => $XMLObject,
    %Options,
);
exit 1 if !$WriteFileSuccess;

# internal functions

sub _Help {
    my ( $Self, %Param ) = @_;

    print "$Script - Generate module configuration chapter\n";
    print "Copyright (C) 2001-2017 OTRS AG, http://otrs.com/\n";
    print "usage: $Script -m <path to module> -l <language> (optional)"
        . " -o <Output filename> (optional) -s <sort by name 1/0> (optional, enabled by default)\n";
    return 1;
}

sub _GetLanguage {
    my ( $Self, %Param ) = @_;

    return 'en' if !$Param{Language};
    return 'en' if $Param{Language} eq 'en';

    # check if a translation file exists
    my @TranslationFiles = $Self->_DirectoryRead(
        Directory => "$Param{ModulePath}/Kernel/Language/",
        Filter    => "$Param{Language}_*.pm",
        Silent    => 1,
    );

    return 'en' if !@TranslationFiles;

    # translation hash
    $Self->{Translation} = {};

    # load translation values
    for my $TranslationFile (@TranslationFiles) {

        my ( $Path, $Module );
        ( $Path, $Module ) = ( $1, $2 )
            if $TranslationFile =~ m{ \A ( .+ ) / ( [^/]+ ) \.pm \z }xms;

        {
            @ISA = ("Kernel::Language::$Module");
            push @INC, "$Path";
            eval {
                require $Module;    ## nofilter(TidyAll::Plugin::OTRS::Perl::Require)

            };
            $Self->Data();
        }
    }
    return $Param{Language};
}

sub _GetConfigSettings {
    my ( $Self, %Param ) = @_;

    # get all config files from the module
    my @FilesInDirectory = $Self->_DirectoryRead(
        Directory => $Param{ConfigDirectory},
        Filter    => '*.xml',
    );

    if ( scalar @FilesInDirectory == 0 ) {
        print "No config files found in $Param{ConfigDiretory}";
        exit 1;
    }

    # to store config settings from the original file
    my %ConfigSettings;

    for my $FileLocation (@FilesInDirectory) {

        my $ParseSuccess = $Self->_ParseConfigFile(
            FileLocation   => $FileLocation,
            ConfigSettings => \%ConfigSettings,
        );

        if ( !$ParseSuccess ) {
            exit 1;
        }

        # output
        print "Parsed file: $FileLocation...done.\n"
    }

    #output
    print "\n";

    return %ConfigSettings;
}

sub _ParseConfigFile {
    my ( $Self, %Param ) = @_;

    # check needed parameters
    for my $Needed (qw(FileLocation ConfigSettings)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    my $FileLocation = $Param{FileLocation};

    # check for file in file system
    return if !$FileLocation;
    if ( !-e $FileLocation ) {
        print "Config file $FileLocation does not exists!";
        return;
    }
    if ( !-r $FileLocation ) {
        print "Config file $FileLocation could not be read!";
        return;
    }

    my $XMLObject = OTRS::XML::Simple->new();

    # convert XML file to perl structure
    my $ParsedSettings;
    eval {
        $ParsedSettings = $XMLObject->XMLin($FileLocation);
    };

    # remove not needed (for documentation)
    if ( ref $ParsedSettings->{ConfigItem} eq 'ARRAY' ) {
        for my $Setting ( @{ $ParsedSettings->{ConfigItem} } ) {
            delete $Setting->{'Setting'};
        }
    }
    else {
        delete $ParsedSettings->{ConfigItem}->{'Setting'}
    }

    # check for conversion errors
    if ($@) {
        print "There was an error parsing XML config file: $@";
        return;
    }

    # remove XML extension
    my $Filename = fileparse($FileLocation);
    $Filename =~ s{\A(.+?) \. .+\z}{$1}xms;

    # add parsed config file to global config settings parameter
    $Param{ConfigSettings}->{$Filename} = $ParsedSettings;

    return 1;
}

sub _CreateDocbookConfigChapter {
    my ( $Self, %Param ) = @_;

    # check needed parameters
    for my $Needed (qw(ConfigSettings)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    # set basic structure
    my %Docbook = (
        chapter => {
            title => 'Configuration',
            para =>
                'The package can be configured via the SysConfig in the Admin Interface. The following configuration options are available:',
            section => [],
        },
    );

    my @ConvertedSettings;

    for my $SettingFile ( sort keys %{ $Param{ConfigSettings} } ) {

        # output
        print "Processing $SettingFile.xml\n";

        if ( ref $Param{ConfigSettings}->{$SettingFile}->{ConfigItem} ne 'ARRAY' ) {
            $Param{ConfigSettings}->{$SettingFile}->{ConfigItem} =
                [ $Param{ConfigSettings}->{$SettingFile}->{ConfigItem} ];
        }

        for my $Setting (
            sort _SortYesNo @{ $Param{ConfigSettings}->{$SettingFile}->{ConfigItem} }
            )
        {

            my $DescriptionContent;

            if ( ref $Setting->{Description} ne 'ARRAY' ) {
                $Setting->{Description} = [ $Setting->{Description} ];
            }

            DESCRIPTION:
            for my $Description ( @{ $Setting->{Description} } ) {

                # for legacy documentation with individual languages
                if ( $Description->{Lang} ) {
                    next DESCRIPTION if $Description->{Lang} ne $Param{Language};

                    $DescriptionContent = $Description->{content};
                    last DESCRIPTION;
                }

                # only items with 'Translatable' flag from here
                next DESCRIPTION if !$Description->{Translatable};

                # get original (English) description first
                $DescriptionContent = $Description->{content};

                # check for translation
                if ( $Self->{Translation}->{$DescriptionContent} ) {
                    $DescriptionContent = $Self->{Translation}->{$DescriptionContent};
                }

                last DESCRIPTION;
            }

            push @ConvertedSettings, {
                title => $Setting->{Name} . ".",
                para  => [
                    "Group: $Setting->{Group}, Subgroup: $Setting->{SubGroup}.",
                    $DescriptionContent,
                ],
            };

            # output
            print "\t Added setting: $Setting->{Name}...done\n";
        }
    }

    $Docbook{chapter}->{section} = \@ConvertedSettings;

    #output
    print "\nGenerating Docbook structure...";

    # convert perl structure into XML structure
    my $ConfigChapter = eval {
        $XMLObject->XMLout(
            \%Docbook,
            NoAttr   => 1,
            KeepRoot => 1
        );
    };

    if ($@) {
        print "\nThere was an error converting settings into XML: $@";
        return;
    }

    # indentation = 4 spaces
    my $Indentation = '    ';
    $ConfigChapter =~ s{[ ]{2}}{$Indentation}gmx;

    # output
    print "done\n";

    return $ConfigChapter;
}

sub _SortYesNo {
    my $Param = $@;

    if ( $Options{SortByName} ) {
        return $a->{Name} cmp $b->{Name};
    }

    return 0;
}

exit 0;
