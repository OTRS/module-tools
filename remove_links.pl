#!/usr/bin/perl -w

# $Id: remove_links.pl,v 1.1.1.1 2004-09-05 01:40:27 martin Exp $

use strict;

my $Dest = shift || die "Need Application-Root location as ARG1";
if (! -d $Dest) {
    die "ERROR: invalid Application-Root directory '$Dest'";
}

my @Dirs = ();
my $Start = $Dest;
R($Start);

sub R {
    my $In = shift;
    my @List = glob("$In/*");
    foreach my $File (@List) {
        $File =~ s/\/\//\//g;
        if (-d $File) {
            R($File);
#            $File =~ s/$Start//;
#            print "Directory: $File\n";
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
#            print "File: $File\n";
#            my $Dir =~ s/^(.*)\//$1/;
            if (-l $OrigFile) {
                print "Unlink Symlink: $File\n";
                unlink $OrigFile || die $!;
            }
        }
    }
}
