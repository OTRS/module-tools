#!/usr/bin/perl -w

# $Id: link.pl,v 1.1.1.1 2004-09-05 01:40:27 martin Exp $

use strict;

my $Source = shift || die "Need Module CVS location as ARG0";
if (! -d $Source) {
    die "ERROR: invalid Module CVS directory '$Source'";
}
my $Dest = shift || die "Need Application-Root location as ARG1";
if (! -d $Dest) {
    die "ERROR: invalid Application-Root directory '$Dest'";
}

my @Dirs = ();
my $Start = $Source;
R($Start);

sub R {
    my $In = shift;
    my @List = glob("$In/*");
    foreach my $File (@List) {
        $File =~ s/\/\//\//g;
        if (-d $File) {
            R($File);
            $File =~ s/$Start//;
#            print "Directory: $File\n";
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
#            print "File: $File\n";
#            my $Dir =~ s/^(.*)\//$1/;
            if (!-e"$Dest/$File" || (-l "$Dest/$File" && unlink ("$Dest/$File"))) {
                if (!symlink ($OrigFile, "$Dest/$File")) {
                    die "Can't link: $!";
                }
                else {
                    print "Link File: $OrigFile -> $Dest/$File\n";
                }
            }
            elsif (-e "$Dest/$File") {
                die "Can't link, file already exists: $Dest/$File";
            }
#            system ("");
        }
    }
}
