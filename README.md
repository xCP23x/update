#Update Script

A simple update script for pkgng, ports and FreeBSD base system with ZFS snapshot management, written in bash.

##Script Features

* Automatic ZFS snapshot creation and deletion
* Updates all pkgng packages
* Updates any additional locked packages via ports using portupgrade
* Fetches (but doesn't install!) FreeBSD system updates
* Supports FreeBSD with ZFS only, and requires sysutils/portupgrade

##ZFS Snapshot Management

By default, a shapshot of zstore/usr/local is created and retained for 7 days. The retention time and location(s) can be modified in the configuration section at the top of the script.

A summary of snapshot disk usage (and disk freed from deletion) is displayed on each run.

##Ports Functionality

This script assumes that any unlocked packages can be safely upgraded via pkgng, and that any locked packages can only be upgraded via ports. After upgrading packages, the script will unlock all locked packages, attempt to upgrade them via portupgrade and then relock them. Only locked packages will be upgraded via ports.

This allows custom compile options to be maintained whilst still allowing automatic updating.

A temporary file (locked.packages) is created during this process - if the script is interrupted (for example ^C), it will automatically relock all packages before continuing. This file is deleted upon completion.

Any vulnerable packages (from `pkg audit`) will also be upgraded via ports if no pkgng upgrade is available.
