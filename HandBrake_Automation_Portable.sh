#!/bin/bash

###################################################################################################################
# DESCRIPTION:     Video compression script that uses HandBrakeCLI for encoding: this version takes every valid   #
#                  file larger than "FileSizeLimit" GB in "CompressDir" and compresses it. When completed, the    #
#                  script moves the uncompressed file into a backup directory.                                    #
#                  Script arguments:                                                                              #
#                            1 - directory of files to compress                                                   #
#                            2 - directory to store backup uncompressed files                                     #
#                            3 - directory containing HandBrake preset files                                      #
#                            4 - (OPTIONAL) directory to place log files                                          #
#                                                                                                                 #
# ADDITIONAL INFO: Dependancies:                                                                                  #
#                  - HandBrakeCLI version 1.2.1 or later (use latest build found at                               #
#                    https://launchpad.net/~stebbins/+archive/ubuntu/handbrake-releases/+packages)                #
#                                                                                                                 #
# AUTHOR:          Marcus Mueller                                                                                 #
###################################################################################################################

# resolve any symlinks of there are any
ThisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

HELP="Usage:\n \
      \t$ThisScript [1] [2] [3] [(optional) 4]\n \
      \t1) [directory to scan]\n \
      \t2) [directory to store backup uncompressed files]\n \
      \t3) [directory containing HandBrake preset files]\n \
      \t4) [(OPTIONAL) directory to place logs]\n \
      \tThe log directory defaults to the backup directory (2) \
     "

if [ -z "$1" ]; then
    echo -e $HELP
    exit 1
elif [ "$1" == "--help" ] || [ "$1" == "-help" ] || [ "$1" == "help" ] ||
     [ "$1" == "h" ] || [ "$1" == "-h" ] || [ "$1" == "--h" ]; then
    echo -e $HELP
    exit 0
elif [ ! -d "$1" ]; then
    echo -e "Could not find directory $1: does not exist"
    echo -e $HELP
    exit 1
else
    CompressDir=$(realpath "$1")
fi

if [ -z "$2" ]; then
    echo -e "No backup directory supplied"
    echo -e $HELP
    exit 1
elif [ ! -d "$2" ]; then
    echo -e "Could not find directory $2: does not exist"
    echo -e $HELP
    exit 1
elif [ "$1" = "$2" ]; then
    echo "The compress directory and backup directory cannot be the same!"
    exit 1
else
    BackupDir=$(realpath "$2")
fi

if [ -z "$3" ]; then
    echo -e "No preset directory supplied"
    echo -e $HELP
    exit 1
elif [ ! -d "$3" ]; then
    echo -e "Could not find directory $3: does not exist"
    echo -e $HELP
    exit 1
else
    PresetsDir=$(realpath "$3")
fi

if [ -z "$4" ]; then
    LogDir="$BackupDir"
elif [ ! -d "$4" ]; then
    echo -e "Could not find directory $4: does not exist"
    echo -e $HELP
    exit 1
else
    LogDir=$(realpath "$4")
fi

# TODO:
# this script will only compress a movie file if it is larger than this size
FileSizeLimit=+14G

# TODO:
# modify this list of file types to choose what kind of video files we should look for
validFileExtensions=(
  .mkv
  .mp4
  .avi
)

echo "Compress directory: $CompressDir"
echo "Backup directory: $BackupDir"
echo "Preset directory: $PresetsDir"
echo "Log directory: $LogDir"

MkvPresetFile="MKV HQ.json"
Mp4PresetFile="MP4 HQ.json"
MkvHqPreset="HQ MKV"
Mp4HqPreset="HQ MP4"

# the log files will be stored in the backup directory
  LogFile="$LogDir/CompressionLoghbs.log"
ErrorFile="$LogDir/HandBrakeScriptErrorReporthbs.log"

# make sure the preset files exist
if [ ! -f "$PresetsDir/$MkvPresetFile" ]; then
  echo "Could not find preset file: $PresetsDir/$MkvPresetFile"
  exit 1
fi

if [ ! -f "$PresetsDir/$Mp4PresetFile" ]; then
  echo "Could not find preset file: $PresetsDir/$Mp4PresetFile"
  exit 1
fi

mkvFileExt=.mkv
mp4FileExt=.mp4

# default to mkv for now
compressFileExt=$mkvFileExt

destinationTmpFormat=.hbtmp

# this function checks for an empty directory
#   inputs:  the file path to check
#   outputs: 0 if empty, 1 if not
checkEmptyDir()
{
  if [ -z "$(ls -A "$1")" ]; then
    return 0
  else
    return 1
  fi
}

# this function checks if a process is running
#   inputs: the name of the process
#   outputs: 0 if the process is running, 1 if not
checkProcess()
{
  if [ "$(pgrep "$1")" ]; then
    return 0
  else
    return 1
  fi
}

# this function will test the given file to see if it can be compressed by HandBrake
#   inputs:  the file path of the media file
#   outputs: 0 if file is valid, 1 if not
checkValidFile()
{
  # make sure another HandBrakeCLI is not already running
  if checkProcess "HandBrakeCLI"; then
    echo "There is another HandBrakeCLI process running. We are exiting so we don't bog down the CPU."
    echo "Exiting..."
    exit 1
  fi
  # make sure the file is not open before compressing it
  if [ "$(lsof "$1")" ]; then
    # create this variable in hopes that the file is being
    # processed and will be ready to compress at the end
    echo "Movie file $1 was open! Skipping for now..."
    RecallFile="$1"
    RecallFileBase="$destFileBase"
    return 1
  # make sure the file is larger than the limit
  elif [ ! "$(find "$1" -size "$FileSizeLimit")" ]; then
    echo "$1 is below the minimum file size limit to compress. Skipping..." >> "$LogFile"
    return 1
  else
    return 0
  fi
}

# this function uses HandBrakeCLI to compress the given movie file
#   inputs:  the file path of the media file
#   outputs: none
compressFile()
{
  uncompressedVideoFileFullPath="$1"
  uncompressedVideoFile=$(basename "$1")
  compressedVideoFileTitle="${1%.*}"
  compressedVideoFileBase=$(basename "$compressedVideoFileTitle")

  # the MP4 container does not support Dolby Atmos or subtitle streams. Use a different preset if we are compressing to MP4
  if [ "$compressFileExt" = "$mkvFileExt" ]; then
    # run HandBrake: video - HQ 1080p, audio - surround passthrough,
    # AC-3 secondary stereo, backup codec: AC3, bitrate: AudioBitrate kb/s
    HandBrakeCLI --input "$uncompressedVideoFileFullPath" \
                 --output "$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir/$MkvPresetFile" \
                 --preset "$MkvHqPreset" \;
  else
    HandBrakeCLI --input "$uncompressedVideoFileFullPath" \
                 --output "$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir$Mp4PresetFile" \
                 --preset "$Mp4HqPreset" \;
  fi

  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile successfully finished compressing" >> "$LogFile"
  else
      echo "HandBrakeCLI did not exit with a return value of 0 while compressing $uncompressedVideoFile. Consider investigating?" >> "$ErrorFile"
  fi

  if [ ! -d "$BackupDir" ]; then
      mkdir -p "$BackupDir"
  fi

  mv "$uncompressedVideoFileFullPath" "$BackupDir/"
  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile is now located in $BackupDir"
      
      # rename to compressed file to the correct file extension
      mv "$compressedVideoFileTitle$destinationTmpFormat" "$compressedVideoFileTitle$compressFileExt"
  else
      echo "Could not move $uncompressedVideoFile to $BackupDir. If this happens, the program may not have the required permissions!" >> "$ErrorFile"
  fi

  # wait 3 seconds so the previous process can gracefully close (hopefully)
  sleep 3
}

# this function walks through a directory tree and attempts to compress any valid files within it.
# all files within the directory tree that are not valid are ignored
#   inputs:  the file path of the directory to seach for compressable files
#   outputs: none
fileTreeWalker()
{
  for file in "$1"/*; do
    # this file is a directory
    if [ -d "$file" ]; then
      # check if the directory is not empty, if so drill down into it
      if ! checkEmptyDir "$file"; then
        fileTreeWalker "$file"
      fi
    # this is a regular file
    elif [ -f "$file" ]; then
      # go through valid files list
      for extension in "${validFileExtensions[@]}"; do
        fileExt=".${file##*.}"
        
        if [ "$fileExt" == "$extension" ]; then
          # account for mp4/m4a files which do not support unburned subtitles
          if [ "$extension" == ".mp4" ] || [ "$extension" == ".m4a" ]; then
            compressFileExt=$mp4FileExt
          else
            compressFileExt=$mkvFileExt
          fi
          
          echo "Found a movie file: $(basename "$file")"
          compressFile "$file"
        fi
      done
    fi
  done
}


# make sure HandBrakeCLI is not already running
if checkProcess "HandBrakeCLI"; then
  echo "Existing HandBrakeCLI process detected. No need to start another compression."
  echo "Exiting..."
  exit 1
fi

fileTreeWalker "$CompressDir"

# check if the recall file exists, and if so
# check if it can now be compressed
if [ ! -z $RecallFile ]; then
  echo "Recall file: $RecallFile"
  echo "Recall base: $RecallFileBase"
  if checkValidFile "$RecallFile"; then
    compressFile "$RecallFile" "$RecallFileBase"
  fi
fi

exit 0
