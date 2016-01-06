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

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use Getopt::Std qw();

sub PrintHelp {
    print <<"EOF";
EOF
}

# get options
my %Opts = ();
Getopt::Std::getopt( 'ohsf', \%Opts );
if ( $Opts{h} ) {
    PrintHelp();
    exit 1;
}

if ( !$Opts{f} || !-r $Opts{f} ) {
    print STDERR "Cannot open file $Opts{f}\n";
    PrintHelp();
    exit 1;
}

my $FH;
open( $FH, '<', $Opts{f} ) || die 'Cannot open file';    ## no critic

my $Content = join( '', <$FH> );

# only current section
my $Section;

# NEW STYLE, MARKDOWN
if ( $Content =~ m{\A\#\d} ) {
    ($Section) = $Content =~ m{ ( ^ \# \d+ \. \d+ \. .*? ) ^ \# \d+ \. \d+ \. }smx;

    # generate wiki-style list, cut out dates
    $Section =~ s{ ^ [ ] - [ ] \d{4}-\d{2}-\d{2} [ ] }{   * }smxg;

    # format bug links
    $Section
        =~ s{ (?:Fixed [ ])? bug\# \[( \d{4,6} )\]\(.*?\) }{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]]}ismxg;
}

# OLD STYLE
else {
    ($Section) = $Content =~ m{ ( ^ \d+ \. \d+ \. .*? ) ^ \d+ \. \d+ \. }smx;

    # generate wiki-style list, cut out dates
    $Section =~ s{ ^ [ ] - [ ] \d{4}-\d{2}-\d{2} [ ] }{   * }smxg;

    # format bug links
    $Section
        =~ s{ Fixed [ ] bug\# ( \d{4,6} ) }{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]]}ismxg;
}

# mask WikiWords
$Section =~ s{(\s) ( [A-Z]+[a-z]+[A-Z]+[a-z]* ) }{$1!$2}smxg;

# mask HTML tags
$Section =~ s{<}{&lt;}smxg;
$Section =~ s{>}{&gt;}smxg;

# mask markdown code delimiter
$Section =~ s{`}{=}smxg;

print $Section;

close($FH);

exit(0);
