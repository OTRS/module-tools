#!/usr/bin/perl -w

# $Id: link.pl,v 1.3 2004-10-25 06:14:52 martin Exp $

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
        if (-d $File && $File !~ /CVS/) {
            R($File);
            $File =~ s/$Start//;
#            print "Directory: $File\n";
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
#            print "File: $File\n";
#            my $Dir =~ s/^(.*)\//$1/;
          if ($File !~ /Entries|Repository|Root|CVS/) {
            if (!-e"$Dest/$File" || (-l "$Dest/$File" && unlink ("$Dest/$File"))) {
                if (!-e $Dest) {
                    die "ERROR: No such directory: $Dest";
                }
                elsif (!-e $OrigFile) {
                    die "ERROR: No such orig file: $OrigFile";
                }
                elsif (!symlink ($OrigFile, "$Dest/$File")) {
#                    die "ERROR: Can't link ($OrigFile->$Dest/$File): $!";
                    die "ERROR: Can't link: $!";
                }
                else {
                    print "NOTICE: Link: $OrigFile -> \n";
                    print "NOTICE:       $Dest/$File\n";
                }
            }
            elsif (-e "$Dest/$File") {
                die "ERROR: Can't link, file already exists: $Dest/$File";
            }
          }
#            system ("");
        }
    }
}
