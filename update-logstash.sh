#!/bin/bash
# This script is intended to run from the git repo's directory. It will pull the latest configuration,
# copy logstash's config files to the system, and restart logstash if necessary.
#
# Use it after changing the logstash config in git, or if you are really daring, as a cronjob to
# keep the system updated to the latest config.

# Switch to script's directory
cd "${0%/*}"

# Update git
git pull
if [ $? -ne 0 ]; then
    echo "Error updating git repository" > /dev/stderr
    exit 1
fi

# Sync config files with git to /etc/logstash/conf.d - this deletes any changes in logstash config that weren't committed to git!
echo "Copying config files"

# With the -i flag, and not using -v, rsync only outputs anything if changes were made to the files
RSYNC_COMMAND=$(rsync -aWi --delete ./logstash/conf.d/ /etc/logstash/conf.d/)

if [ $? -eq 0 ]; then
    # rsync succeeded

    if [ -n "${RSYNC_COMMAND}" ]; then
        # Changes were made
        echo "Config updated - reloading logstash"
        pkill -u logstash --signal HUP
    else
        echo "No config changes were made"
    fi
else
    echo "Error running rsync" > /dev/stderr
    exit 1
fi


