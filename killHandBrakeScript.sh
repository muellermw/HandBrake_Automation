#!/bin/bash
# This script checks if any HandBrake_Automation script is running. If so:
# kills both the script and the HandBrakeCLI process running along with it.

compressionScript="HandBrake_Auto"
compressionProcess="HandBrakeCLI"

pkill $compressionScript

if [ $? -eq 0 ]; then
  pkill $compressionProcess
  echo "Script killed"
else
  echo "Script not detected"
fi

exit 0
