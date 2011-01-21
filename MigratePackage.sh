#!/bin/bash

# --
# module-tools/MigratePackage.sh
#   - script for migrating package to a certain OTRS release.
# Copyright (C) 2001-2011 OTRS AG, http://otrs.org/
# --
# $Id: MigratePackage.sh,v 1.2 2011-01-21 12:39:18 mae Exp $
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

# TODO:
# * verbose/non-verbose mode
# * some error handling
# * setting new OldId of patched file
# * clean up inside of tmp dir
# * maybe: force mode - if file versions are not matching
#

# version detection
VERSION=$(echo "\$Revision: 1.2 $" | awk '{print $2}');

# flag definition
DEBUG=
VERBOSE=

# needed params
MODULE=
SOURCE=
TARGET=

# create temp dir
TMP_BASE_DIR="/tmp"
PID=$$
TMP_DIR="${TMP_BASE_DIR}/otrs_auto_migrate_${PID}"

# package excludes
PKG_EXCLUDE_SOPM=" ! -name *.sopm "
PKG_EXCLUDE_DOC=" ! -path */doc/* "
PKG_EXCLUDE_CONF=" ! -path */Kernel/Config/Files/* "

# function for printing out usage and exit
function usage {
    echo -e \
        "usage: $0 [-d] [-v] [-m module path] [-s source path] [-t target path] \n" \
        "\tVersion: $VERSION \n" \
        "\t-d: enable shell debug mode \n" \
        "\t-v: enable verbose mode \n" \
        "\t-m: /path/to/custom/package \n" \
        "\t-s: /path/to/otrs - current OTRS version on which package is based on \n" \
        "\t-t: /path/to/otrs - target OTRS version on which package should be migrated \n" \
        >&2
    exit 1
}

# function for creating temp dir
function create_temp {
    TEMP_DIR=$1

    # sanity check for temp dir
    if [ -d "$TEMP_DIR" ]; then
        echo "Temp directory $TEMP_DIR already exits already, exiting."
        exit 1;
    fi

    echo -n "Creating temp directory '$TEMP_DIR': "
    mkdir $TEMP_DIR

    if [ "x$?" != "x0" ]; then
        echo "failed, exiting!"
        exit 1
    fi

    echo "done."
}

# function for clean up temp dir
function cleanup_temp {
    TEMP_DIR=$1

    if [ -d "$TEMP_DIR" ]; then
        echo -n "Removing temp directory '$TEMP_DIR': "
        rm -rf $TEMP_DIR

        if [ "x$?" != "x0" ]; then
            echo "failed!"
        fi

        echo "done."
    fi
}

# function to create a diff from package file to framework file
function create_diff {
    TEMP_DIR=$1
    FW_FILE=$2
    PKG_FILE=$3

    # get base of package file
    PATCH_FILE=$(basename $PKG_FILE)

    # first perl part removes patching of Id and OldId
    # second perl part removes VERSION patching
    echo -n "- generating patch file - "
    diff -u $FW_FILE $PKG_FILE \
        | perl -le '$PatchContent = join("", <STDIN>); $PatchContent =~ s{ (?: @@ .*? @@\n .*? Id            .*? [^@@]+ ) }{}xms; print $PatchContent' \
        | perl -le '$PatchContent = join("", <STDIN>); $PatchContent =~ s{ (?: @@ .*? @@\n .*? VERSION \s+ = .*? [^@@]+ ) }{}xms; print $PatchContent' \
        > ${TEMP_DIR}/${PATCH_FILE}.patch
    if [ "x$?" != "x0" ]; then
        echo -n "- patch file creation failed - "
        return 1
    fi
}

function create_pkg_file {
    TEMP_DIR=$1
    FW_FILE=$2
    PKG_FILE=$3

    # get base of package file
    PKG_BASENAME=$(basename $PKG_FILE)
    PATCH_FILE="${TEMP_DIR}/${PKG_BASENAME}.patch"

    # copy framework file to temp dir
    cp $FW_FILE ${TEMP_DIR}/${PKG_BASENAME}

    # apply patch to file
    patch -p0 ${TEMP_DIR}/${PKG_BASENAME} < $PATCH_FILE 1>/dev/null
    if [ "x$?" != "x0" ]; then
        echo -n "- patching failed - "
        return 1
    fi
}

# function to find framework file of package file
# and create patches and new package files
function handle_pkg_file {
    PKG_FILE=$1

    # get line with OldId
    old_id=$(grep "^# \$OldId" $PKG_FILE)
    if [ "x${old_id}" = "x" ]; then
        echo -n "- no 'OldId' file markers - "
        return 1
    fi

    # extract needed data
    old_file_name=$(echo $old_id | sed -e 's/.*OldId: \([A-Za-z0-9.]*\),.*/\1/' )
    if [ "x${old_file_name}" = "x" ]; then
        echo -n "- unable to extract framework file name - "
        return 1
    fi

    # get CVS OldId of file
    old_file_id=$(echo $old_id | sed -e 's/.*,v \([0-9]*\(\.[0-9]*\)*\).*/\1/' )
    if [ "x${old_file_id}" = "x" ]; then
        echo -n "- unable to extract framework file Id - "
        return 1
    fi

    # try find file source framework directory
    source_fw_file=$(find $SOURCE -type f -name "$old_file_name")
    if [ "x${source_fw_file}" = "x" ]; then
        echo -n "- not a framework file - "
        return 1
    fi

    # get line with Id in framework file
    fw_id=$(grep "^# \$Id" $source_fw_file)
    if [ "x${fw_id}" = "x" ]; then
        echo -n "- no 'Id' file markers - "
        return 1
    fi

    # get CVS Id of file
    fw_file_id=$(echo $fw_id | sed -e 's/.*,v \([0-9]*\(\.[0-9]*\)*\).*/\1/' )
    if [ "x${fw_file_id}" = "x" ]; then
        echo -n "- unable to extract framework file Id - "
        return 1
    fi

    # check file IDs
    if [ "x$old_file_id" != "x$fw_file_id" ]; then
        echo -n " - file ID mismatch - "
        return 1
    fi

    # create diff for package files
    create_diff $TMP_DIR $source_fw_file $PKG_FILE
    if [ "x$?" != "x0" ]; then
        return 1
    fi

    # find new framework file
    target_fw_file=$(find $TARGET -type f -name "$old_file_name")
    if [ "x${target_fw_file}" = "x" ]; then
        echo -n "- not a framework file - "
        return 1
    fi

    # create package file based on framework file
    create_pkg_file $TMP_DIR $target_fw_file $PKG_FILE
}

# get submitted params
while getopts "dvm:s:t:" opt
do
    case "$opt" in
        d)    DEBUG=on;;
        v)    VERBOSE=on;;
        m)    MODULE="$OPTARG";;
        s)    SOURCE="$OPTARG";;
        t)    TARGET="$OPTARG";;
        \?)   # unknown flag
            usage
            ;;
    esac
done
shift `expr $OPTIND - 1`

# check for turning on shell debug mode
if [ "x${DEBUG}" != "x" ]; then
    set -x
fi

# check for needed arguments
if [ "x${MODULE}" = "x" -o "x${SOURCE}" = "x" -o "x${TARGET}" = "x" ]; then
    usage
fi

# check for needed directories
for directory_check in $MODULE $SOURCE $TARGET
do
    echo -n "Checking for ${directory_check}: "
    if [ ! -d "$directory_check" ]; then
        echo "failed!"
        exit 1
    fi
    echo "done."
done

create_temp $TMP_DIR

PKG_EXCLUDE="$PKG_EXCLUDE_SOPM $PKG_EXCLUDE_DOC $PKG_EXCLUDE_CONF"
for package_file in `find $MODULE ! -path '*/CVS/*' ! -name "CVS" $PKG_EXCLUDE -type f`
do
    echo -n "Handling file '$package_file': "

    # try to find related frame work file
    handle_pkg_file $package_file

    if [ "x$?" != "x0" ]; then
        echo "failed, finishing!"
        continue
    fi

    echo "done."
done

#cleanup_temp $TMP_DIR
