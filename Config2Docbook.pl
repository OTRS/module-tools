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

## nofilter(TidyAll::Plugin::OTRS::Perl::PerlCritic)

package OTRS::XML::Simple;

eval { require XML::Simple };
if ($@) {
    print "Can't load XML::Simple: $@";
    exit 1;
}

use base 'XML::Simple';

# Override the sort method form XML::Simple
sub sorted_keys {    ## no critic
    my ( $Self, $Name, $Hashref ) = @_;

    # only change sort order for chapter
    if ( $Name eq 'chapter' ) {

        # set the right sort order
        return ( 'title', 'para', 'section', );
    }

    # only change sort order for section
    if ( $Name eq 'section' ) {

        # set the right sort order
        return ( 'title', 'para', );
    }

    return $Self->SUPER::sorted_keys( $Name, $Hashref );    ## no critic
}

# main Config2Docbook program
package main;
use strict;
use warnings;

use File::Basename;

use vars (qw($Self));
use Getopt::Std;

print "\nDEPRECATED! better use GenerateConfigChapter.pl!\n\n";

eval { require XML::Simple };
if ($@) {
    print "Can't load XML::Simple: $@";
    exit 1;
}

# get options
my %Opts = ();
getopt( 'hmols', \%Opts );

if ( $Opts{h} ) {
    _Help();
    exit 1;
}

# check for module parameter
if ( !$Opts{m} ) {
    _Help();
    print "\n missing path to module\n";
    print "Example: Config2Docbook -m /Modules/MyModule\n";
    exit 1;
}

my %Options;

# set full module path to config files
$Opts{m} =~ s{(.+)/\z}{$1}smx;
$Options{ConfigDirectory} = $Opts{m} . '/Kernel/Config/Files';

# set output language
my $Language;
use vars qw(@ISA);
my $Self = {};
bless($Self);

if ( $Opts{l} && $Opts{l} eq 'en' ) {

    # always allow plain english
    $Language = 'en';
}
elsif ( $Opts{l} ) {

    # check if a translation file exists
    my @TranslationFiles = _DirectoryRead(
        Directory => "$Opts{m}/Kernel/Language/",
        Filter    => "$Opts{l}_*.pm",
        Silent    => 1,
    );
    if (@TranslationFiles) {

        # set desired language
        $Language = $Opts{l};

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
                eval "require $Module";
                $Self->Data();
            }
        }
    }
    else {

        # default to english
        $Language = 'en';
    }
}
else {

    # default to english
    $Language = 'en';
}

# set output file
my $OutputFile = 'ConfigChapter.xml';
if ( $Opts{o} ) {
    $OutputFile = $Opts{o} . '.xml';
}
$Options{OutputLocation} = $Opts{m} . '/doc/' . $Language . '/' . $OutputFile;

# create parser in / out object
my $XMLObject = new OTRS::XML::Simple;

# output
print "+----------------------------------------------------------------------------+\n";
print "| Convert config files to Docbook:\n";
print "| Module: $Opts{m}\n";
print "| From:   $Options{ConfigDirectory}\n";
print "| To:     $Options{OutputLocation}\n";
print "+----------------------------------------------------------------------------+\n";

# get all config files from the module
my @FilesInDirectory = _DirectoryRead(
    Directory => $Options{ConfigDirectory},
    Filter    => '*.xml',
);

if ( scalar @FilesInDirectory == 0 ) {
    print "No config files found in $Options{ConfigDiretory}";
    exit 1;
}

# to store config settings from the original file
my %ConfigSettings;

for my $FileLocation (@FilesInDirectory) {

    my $ParseSuccess = _ParseConfigFile(
        FileLocation   => $FileLocation,
        ConfigSettings => \%ConfigSettings
    );

    if ( !$ParseSuccess ) {
        exit 1;
    }

    # output
    print "Parsed file: $FileLocation...done.\n"
}

#output
print "\n";

# set sorting parameter
$Self->{SortByName} = $Opts{s};

# generate XML docbook config chapter based in config file
my $ConfigChapter = _CreateDocbookConfigChapter( ConfigSettings => \%ConfigSettings );

if ( !$ConfigChapter ) {
    exit 1;
}

# write the XML file in the file system
my $WriteFileSuccess = _WriteDocbookFile(
    ConfigChapter => $ConfigChapter,
    %Options,
);

if ( !$WriteFileSuccess ) {
    exit 1;
}

# internal functions

sub _Help {
    my %Param = @_;

    print "Config2Docbook.pl - Convert sysc config settings to Docbook"
        . " format\n";
    print "Copyright (C) 2001-2017 OTRS AG, http://otrs.com/\n";
    print "usage: Config2Docbook.pl -m <path to module> -l <language> (optional)"
        . " -o <Output filename> (optional) -s <sort by name 1/0> (optional)\n";
}

sub _ParseConfigFile {
    my %Param = @_;

    # check needed parameters
    for my $Needed (qw(FileLocation ConfigSettings)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    my $FileLocation = $Param{FileLocation};

    # check for file in filesystem
    return if !$FileLocation;
    if ( !-e $FileLocation ) {
        print "Config file $FileLocation does not exists!";
        return;
    }
    if ( !-r $FileLocation ) {
        print "Config file $FileLocation could not be read!";
        return;
    }

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

    # add parsed config file to global config settings parmeter
    $Param{ConfigSettings}->{$Filename} = $ParsedSettings;

    return 1;
}

sub _CreateDocbookConfigChapter {
    my %Param = @_;

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
        print "Procesing $SettingFile.xml\n";

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
                    next DESCRIPTION if $Description->{Lang} ne $Language;

                    $DescriptionContent = $Description->{content};
                    last DESCRIPTION;
                }

                # only items with 'Translatable' flag from here
                next DESCRIPTION if !$Description->{Translatable};

                # get original (english) description first
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
        print "\nThere was an error converting stettings into XML: $@";
        return;
    }

    # indentation = 4 spaces
    my $Indentation = '    ';
    $ConfigChapter =~ s{[ ]{2}}{$Indentation}gmx;

    # output
    print "done\n";

    return $ConfigChapter;
}

sub _WriteDocbookFile {
    my %Param = @_;

    # check needed parameters
    for my $Needed (qw(ConfigChapter OutputLocation)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    my $ConfigChapter = $Param{ConfigChapter};

    my $BookHeader = <<"XML";
<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.4//EN"
    "http://www.oasis-open.org/docbook/xml/4.4/docbookx.dtd">

<book lang='en'>

XML

    my $BookFooter = <<"XML";

</book>
XML

    # assemble the final file content
    my $Book = $BookHeader . $ConfigChapter . $BookFooter;

    # output
    print "Writing file $Param{OutputLocation}...";

    # write file in filesystem
    my $FileLocation = _FileWrite(
        Location => $Param{OutputLocation},
        Content  => \$Book,
        Mode     => 'utf8'
    );
    return if !$FileLocation;

    # check XML by reading it
    eval {
        $XMLObject->XMLin($FileLocation);
    };
    if ($@) {
        print "\nThere was an error in the output file XML structure: $@";
        return;
    }

    # output
    print "done\n\n";

    return 1
}

# from main.pm

=item DirectoryRead()

reads a directory and returns an array with results.

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/tmp',
        Filter    => 'Filenam*',
    );

    my @FilesInDirectory = _DirectoryRead(
        Directory => $Path,
        Filter    => '*',
    );

You can pass several additional filters at once:

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/tmp',
        Filter    => \@MyFilters,
    );

Use the 'Silent' parameter to suppress messages when a directory
does not have to exist:

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/special/optional/directory/',
        Filter    => '*',
        Silent    => 1,     # will not print errors if the directory does not exist
    );

=cut

sub _DirectoryRead {
    my %Param = @_;

    # check needed params
    for my $Needed (qw(Directory Filter)) {
        if ( !$Param{$Needed} ) {
            print "Needed $Needed: $!\n";
            return;
        }
    }

    # if directory doesn't exists stop
    if ( !-d $Param{Directory} && !$Param{Silent} ) {
        print "Directory doesn't exist: $Param{Directory}: $!";
        return;
    }

    # check Filter param
    if ( ref $Param{Filter} ne '' && ref $Param{Filter} ne 'ARRAY' ) {
        print 'Filter param need to be scalar or array ref!',
            return;
    }

    # prepare non array filter
    if ( ref $Param{Filter} ne 'ARRAY' ) {
        $Param{Filter} = [ $Param{Filter} ];
    }

    # executes glob for every filter
    my @GlobResults;
    my %Seen;

    for my $Filter ( @{ $Param{Filter} } ) {
        my @Glob = glob "$Param{Directory}/$Filter";

        # look for repeated values
        GLOBNAME:
        for my $GlobName (@Glob) {

            next GLOBNAME if !-e $GlobName;

            if ( !$Seen{$GlobName} ) {
                push @GlobResults, $GlobName;
                $Seen{$GlobName} = 1;
            }
        }
    }

    # if clean results
    return if !@GlobResults;

    # compose normalize every name in the file list
    my @Results;
    for my $Filename (@GlobResults) {

        #not sure if this is needed
        #        # first convert filename to utf-8 if utf-8 is used internally
        #        $Filename = $Self->{EncodeObject}->Convert2CharsetInternal(
        #            Text => $Filename,
        #            From => 'utf-8',
        #        );
        #
        #        # second, convert it to combined normalization form (NFC), if it is an utf-8 string
        #        # this has to be done because MacOS stores filenames as NFD on HFS+ partitions,
        #        #   leading to data inconsistencies
        #        if ( Encode::is_utf8($Filename) ) {
        #            $Filename = Unicode::Normalize::NFC($Filename);
        #        }

        push @Results, $Filename;
    }

    # always sort the result
    my @SortedResult = sort @Results;

    return @SortedResult;
}

=item FileWrite()

to write data to file system

    my $FileLocation = _FileWrite(
        Directory => 'c:\some\location',
        Filename  => 'me_to/alal.xml',
        # or Location
        Location  => 'c:\some\location\me_to\alal.xml'

        Content   => \$Content,
    );

    my $FileLocation = _FileWrite(
        Directory  => 'c:\some\location',
        Filename   => 'me_to/alal.xml',
        # or Location
        Location   => 'c:\some\location\me_to\alal.xml'

        Content    => \$Content,
        Mode       => 'binmode', # binmode|utf8
        Type       => 'Local',   # optional - Local|Attachment|MD5
        Permission => '644',     # unix file permissions
    );

=cut

sub _FileWrite {
    my %Param = @_;

    if ( $Param{Filename} && $Param{Directory} ) {

        # filename clean up
        $Param{Filename} = $Self->FilenameCleanUp(
            Filename => $Param{Filename},
            Type     => $Param{Type} || 'Local',    # Local|Attachment|MD5
        );
        $Param{Location} = "$Param{Directory}/$Param{Filename}";
    }
    elsif ( $Param{Location} ) {

        # filename clean up
        $Param{Location} =~ s/\/\//\//g;
    }
    else {
        print 'Need Filename and Directory or Location!';
    }

    # set open mode (if file exists, lock it on open, done by '+<')
    my $Exists;
    if ( -f $Param{Location} ) {
        $Exists = 1;
    }
    my $Mode = '>';
    if ($Exists) {
        $Mode = '+<';
    }
    if ( $Param{Mode} && $Param{Mode} =~ /^(utf8|utf\-8)/i ) {
        $Mode = '>:utf8';
        if ($Exists) {
            $Mode = '+<:utf8';
        }
    }

    # return if file can not open
    my $FH;
    if ( !open $FH, $Mode, $Param{Location} ) {
        print STDERR "ERROR: Can't write '$Param{Location}': $!";
        return;
    }

    # lock file (Exclusive Lock)
    if ( !flock $FH, 2 ) {
        print "Can't lock '$Param{Location}': $!"
    }

    # empty file first (needed if file is open by '+<')
    truncate $FH, 0;

    # not sure if this is needed
    #    # enable binmode
    #    if ( !$Param{Mode} || lc $Param{Mode} eq 'binmode' ) {
    #
    #        # make sure, that no utf8 stamp exists (otherway perl will do auto convert to iso)
    #        $Self->{EncodeObject}->EncodeOutput( $Param{Content} );
    #
    #        # set file handle to binmode
    #        binmode $FH;
    #    }

    # write file if content is not undef
    if ( defined ${ $Param{Content} } ) {
        print $FH ${ $Param{Content} };
    }

    # write empty file if content is undef
    else {
        print $FH '';
    }

    # close the filehandle
    close $FH;

    # set permission
    if ( $Param{Permission} ) {
        if ( length $Param{Permission} == 3 ) {
            $Param{Permission} = "0$Param{Permission}";
        }
        chmod( oct( $Param{Permission} ), $Param{Location} );
    }

    return $Param{Filename} if $Param{Filename};
    return $Param{Location};
}

sub _SortYesNo {
    my $Param = $_[0];

    if ( $Self->{SortByName} ) {
        return $a->{Name} cmp $b->{Name};
    }
    else {
        return 0;
    }
}

exit 0;
