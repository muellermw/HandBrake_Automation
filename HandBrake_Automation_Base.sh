#!/bin/bash

####################################################################################################################
# DESCRIPTION:     Video compression script that uses HandBrakeCLI for encoding: this version takes every          #
#                  .mkv (or .mp4) file in the compress directory and compresses it. When completed, the            #
#                  script moves the compressed file and uncompressed file into finished and backup directories.    #
#                                                                                                                  #
# ADDITIONAL INFO: Dependencies:                                                                                   #
#                  - HandBrakeCLI version 1.2.1 or later (use latest build found at                                #
#                    https://launchpad.net/~stebbins/+archive/ubuntu/handbrake-releases)                           #
#                                                                                                                  #
# AUTHOR:          Marcus Mueller                                                                                  #
####################################################################################################################

# TODO:
# Fill this information in for where the compression should take place,
# where the finished and backup files are placed,
# and where preset files are stored.
CompressDir=""
FinishedDir=""
  BackupDir=""
 PresetsDir="$CompressDir"/HandBrakePresets

# in case we are using relative paths
CompressDir=$(realpath "$CompressDir")
FinishedDir=$(realpath "$FinishedDir")
  BackupDir=$(realpath "$BackupDir")
 PresetsDir=$(realpath "$PresetsDir")

if [ ! -d "$CompressDir" ] || [ ! -d "$PresetsDir" ] || [ -z "$FinishedDir" ] || [ -z "$BackupDir" ]; then
  echo -e "Some parameters are missing or invalid:"
  echo -e "\tCompression Directory: $CompressDir"
  echo -e "\tFinished Directory: $FinishedDir"
  echo -e "\tBackup Directory: $BackupDir"
  echo -e "\tPresets Directory: $PresetsDir"
  exit 1
fi

if [ "$CompressDir" == "$FinishedDir" ]; then
  echo "The compression path cannot be the same as the finished path!"
  exit 1
fi

if [ "$CompressDir" == "$BackupDir" ]; then
  echo "The compression path cannot be the same as the backup path!"
  exit 1
fi

MkvPresetFile="MKV HQ.json"
Mp4PresetFile="MP4 HQ.json"
MkvHqPreset="HQ MKV"
Mp4HqPreset="HQ MP4"

# resolve any symlinks of there are any
ThisScript="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

  LogFile="$CompressDir/CompressionLoghbs.log"
ErrorFile="$CompressDir/HandBrakeScriptErrorReporthbs.log"

mkvFileExt=.mkv
mp4FileExt=.mp4

# TODO: change this is you'd like to compress to mp4 instead
compressFileExt=$mkvFileExt

destinationTmpFormat=.hbtmp

# make sure the preset files exist
if [ "$compressFileExt" == "$mkvFileExt" ] && [ ! -f "$PresetsDir/$MkvPresetFile" ]; then
  echo "Could not find preset file: $PresetsDir/$MkvPresetFile"
  exit 1
elif [ "$compressFileExt" == "$mp4FileExt" ] && [ ! -f "$PresetsDir/$Mp4PresetFile" ]; then
  echo "Could not find preset file: $PresetsDir/$Mp4PresetFile"
  exit 1
fi

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
    echo "Movie file $1 is currently opened by another process! Skipping for now..."
    RecallFile="$1"
    RecallFileBase="$destFileBase"
    return 1
  else
    return 0
  fi
}

# this function uses HandBrakeCLI to compress the given movie file
#   inputs:  the file path of the media file,
#            file base of the media file (relative to the "compress" directory)
#   outputs: none
compressFile()
{
  uncompressedVideoFileFullPath="$1"
  uncompressedVideoFile=$(basename "$1")
  uncompressedVideoFileBase="$2"
  compressedVideoFileTitle="${2%.*}"
  compressedVideoFileBase=$(basename "$compressedVideoFileTitle")

  # the MP4 container does not support Dolby Atmos or subtitle streams. Use a different preset if we are compressing to MP4
  if [ "$compressFileExt" = "$mkvFileExt" ]; then
    # run HandBrake: video - HQ 1080p, audio - surround passthrough,
    # AC-3 secondary stereo, backup codec: AC3
    HandBrakeCLI --input "$CompressDir$uncompressedVideoFileBase" \
                 --output "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir/$MkvPresetFile" \
                 --preset "$MkvHqPreset" \;
  else
    HandBrakeCLI --input "$CompressDir$uncompressedVideoFileBase" \
                 --output "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir/$Mp4PresetFile" \
                 --preset "$Mp4HqPreset" \;
  fi

  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile successfully finished compressing" >> "$LogFile"
  else
      echo "HandBrakeCLI did not exit with a return value of 0 while compressing $uncompressedVideoFile. Consider investigating?" >> "$ErrorFile"
  fi

  if [ ! -d "$FinishedDir" ]; then
      mkdir -p "$FinishedDir"
  fi

  mv "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" "$FinishedDir$compressedVideoFileTitle$compressFileExt"
  if [ $? -eq 0 ]; then
      echo "$compressedVideoFileBase$destinationTmpFormat is now located at $FinishedDir$compressedVideoFileTitle$compressFileExt"
  else
      echo "Could not move $compressedVideoFileBase$destinationTmpFormat to $FinishedDir$compressedVideoFileTitle$compressFileExt. Did HandBrakeCLI error out as well?" >> "$ErrorFile"
  fi

  if [ ! -d "$BackupDir" ]; then
      mkdir -p "$BackupDir"
  fi

  mv "$uncompressedVideoFileFullPath" "$BackupDir/"
  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile is now located in $BackupDir"
  else
      echo "Could not move $uncompressedVideoFile to $BackupDir. If this happens, the program may not have the required permissions!" >> "$ErrorFile"
  fi

  # wait 3 seconds so the previous process can gracefully close (hopefully)
  sleep 3
}

# this function walks through a directory tree and attempts to compress any valid files within it.
# all files within the directory tree that are not valid are restored in the destination directory
#   inputs:  the file path of the directory to seach for compressable files
#   outputs: none
fileTreeWalker()
{
  for file in "$1"/*; do
    # create the new destination file base
    destFileBase=$(echo "$file" | sed "s|$CompressDir||")

    # this file is a directory and is not the preset directory
    if [ -d "$file" ] && [ ! "$file" = "$PresetsDir" ]; then
      # create the new directory in the destination location
      mkdir -p "$FinishedDir$destFileBase"

      # check if the directory is not empty, if so drill down into it
      if ! checkEmptyDir "$file"; then
        fileTreeWalker "$file"
      fi
    # this is a regular file
    elif [ -f "$file" ]; then
      # compare filename patterns with its basename
      case $(basename "$file") in
        $ThisScript)
          echo "$file is my own file, do not move or copy"
          ;;
        $(basename "$LogFile") | $(basename "$ErrorFile"))
          echo "$file is a program log file, do not move or copy"
          ;;
        *$compressFileExt)
          echo "Found a movie file: $(basename "$file")"
          fullMovieFileName=$(realpath "$file")
          if checkValidFile "$fullMovieFileName"; then
            compressFile "$fullMovieFileName" "$destFileBase"
          fi
          ;;
        # this accounts for any files that do not need to be compressed,
        # but rather just moved to the destination
        *)
          mv "$file" "$FinishedDir$destFileBase"
      esac
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

find "$CompressDir" -mindepth 1 -type d -empty -delete

exit 0
