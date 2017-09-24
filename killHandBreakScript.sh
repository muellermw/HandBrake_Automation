#!/bin/sh
# This script checks if any handbrakeScript is running. If so:
# kills both the script and the HandBrakeCLI process running along with it

compressionScript="handbrakeScript"
compressionProcess="HandBrakeCLI"

pkill $compressionScript

if [ $? -eq 0 ]; then
    pkill $compressionProcess
    echo "Script killed"
else
    echo "Script not detected"
fi

