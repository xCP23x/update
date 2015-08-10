#!/usr/bin/env bash

# Updates all packages using pkgng, then updates ports to newest versions
# Any locked packages are unlocked, upgraded from ports, then relocked
# Automatically creates and manages ZFS snapshots
# Checks for (but doesn't install) FreeBSD updates
#
# Comments, suggestions, bug reports please to:
# Chris Price <chris@chrisprice.co>
#
# NOTE: REQUIRES sysutils/portupgrade TO BE INSTALLED


##################################################################
# Config Section:

# Number of days to keep automatic ZFS snapshots
MAXAGE=7

# ZFS datasets to backup on each update
ZFS[0]="zstore/usr/local"

# END OF CONFIG - You shouldn't have to edit after this line
##################################################################


#Ensure that all possible binary paths are checked
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin


# FUNCTIONS


# Snapshot deletion uses a cut down version of https://github.com/xCP23x/backup/blob/master/deleteoldbackups.sh
# Function to set variables for date/time from snapshot name.
getSnapDate() {
    unset SNAPHOSTNAME SNAPYEAR SNAPMONTH SNAPDAY SNAPTIME SNAPDAYS SNAPAGE
    SNAPPREFIX=$(echo "$1" | cut -d - -f 1)
    SNAPYEAR=$(echo "$1" | cut -d - -f 2)
    SNAPMONTH=$(echo "$1" | cut -d - -f 3)
    SNAPDAY=$(echo "$1" | cut -d - -f 4)
    SNAPTIME=$(echo "$1" | cut -d - -f 5)

    # Iterate over possible valid prefixes
    for i in "${ZFS[@]}"; do
        if [ "${SNAPPREFIX}" == "$i@UPDATE" ]; then
            if [[ "${SNAPYEAR}" && "${SNAPMONTH}" && "${SNAPDAY}" && "${SNAPTIME}" ]]; then
                # Approximate a 30-day month and 365-day year
                SNAPDAYS=$(( $((10#${SNAPYEAR}*365)) + $((10#${SNAPMONTH}*30)) + $((10#${SNAPDAY})) ))
                SNAPAGE=$(( 10#${DAYS} - 10#${SNAPDAYS} ))
                return 0
            fi
        fi
    done

    return 1 # It wasn't made by this script
}


# Converts bytes to a human readable format
humanReadable() {
    HUMAN=$(echo "$1" | awk '{ split( "B KiB MiB GiB TiB PiB EiB ZiB YiB", s ); n=1; while( $1>1024 ){ $1/=1024; n++ } printf "%.2f %s", $1, s[n] }')
}


# Function to delete old snapshots
deleteSnaps() {
    # Get current time
    DAY=$(date +%d)
    MONTH=$(date +%m)
    YEAR=$(date +%C%y)

    # Approximate a 30-day month and 365-day year
    DAYS=$(( $((10#${YEAR}*365)) + $((10#${MONTH}*30)) + $((10#${DAY})) ))

    # Count how many snapshots have been deleted/kept, and how much space has been saved/used
    NDELETED=0
    NKEPT=0
    SPACEFREED=0
    SPACEUSED=0

    echo "Checking for old snapshots to delete"

    # Iterate over all snapshots
    # We're using process substitution to avoid subshell problems
    /sbin/zfs list -Ht snapshot | cut -f 1 | {
        while read -r s; do
            KEEPSNAP="NO"
            getSnapDate "$s"

            if [ $? == 0 ]; then    # It's a valid snapshot created by this script

                # Delete backups older than a week
                if [[ ${SNAPAGE} -gt ${MAXAGE} ]]; then
                    # Delete it - leave KEEPSNAP="NO"
                    NDELETED=$(( 10#${NDELETED} + 1 ))
                    SPACEFREED=$(( 10#${SPACEFREED} + $(/sbin/zfs list -Hpt snapshot | grep "$s" | cut -f 2) ))
                else
                    # Mark it to be kept
                    KEEPSNAP="YES"
                    NKEPT=$(( 10#${NKEPT} + 1 ))
                    SPACEUSED=$(( 10#${SPACEUSED} + $(/sbin/zfs list -Hpt snapshot | grep "$s" | cut -f 2) ))
                fi

                if [ ${KEEPSNAP} == "NO" ]; then
                    # Actually delete it
                    /sbin/zfs destroy "$s"
                fi
            fi
        done

        # Output stats
        humanReadable ${SPACEFREED}; echo "Deleted ${NDELETED} snapshots, freeing ${HUMAN}"
        humanReadable ${SPACEUSED}; echo "${NKEPT} snapshots remain, taking up ${HUMAN}"
    }
}


# Function to relock packages
lock() {
    for i in ${LOCKED[@]}; do
        /usr/sbin/pkg lock -y "$i"
    done
}


### START OF SCRIPT ###

# Create a ZFS snapshot
echo "Creating ZFS snapshots"
SNAPSHOTDATE=$(date -u +%Y-%m-%d-%H%M)
for i in "${ZFS[@]}"; do
    /sbin/zfs snapshot "$i"@UPDATE-"${SNAPSHOTDATE}"
done

# Delete old snapshots
deleteSnaps


# Keep track of locked packages
if [ -f "locked.packages" ]; then
    # Previous process killed, re-lock packages and resume
    LOCKED=$(cat locked.packages)
    echo "Found previous state, resuming..."
    lock
else
    # Put locked packages in $LOCKED, write to file in case of ctrl-c
    LOCKED=$(/usr/sbin/pkg query -e '%k=1' %n)
    echo "${LOCKED[@]}" > locked.packages
fi


# Upgrade all unlocked packages
/usr/sbin/pkg upgrade

# Unlock all packages and update ports
/usr/sbin/pkg unlock -aqy
/usr/sbin/portsnap fetch update
/usr/local/sbin/portupgrade -i "${LOCKED[@]}"

# Relock packages
lock
rm locked.packages


# Fetch updates for FreeBSD
/usr/sbin/freebsd-update fetch