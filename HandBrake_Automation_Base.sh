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

# this function uses HandBrakeCLI to compress the given movie file,
# save the output in the "finished" directory, and back up the uncompressed file
#   inputs:  1) the file path of the media file
#            2) file base of the media file (relative to the "compress" directory)
#   outputs: none
compressFile()
{
  # Okay, so this code maintains directory consistency between the "compress" and "finished" directories,
  # but it's atrocious and probably needs to be refactored. However, a whole 3 people are using this script,
  # so I'm just going to make an example scenario along with the code so it makes sense to me down the road
  # when I don't want to read it again. Sound good? Let's go!

  # let's make up sample inputs to this function:
  # $1 = /home/compress/folder1/movieFile.mkv
  # $2 = /folder1/movieFile.mkv
  # $CompressDir = /home/compress
  # $FinishedDir = /home/finished
  # $BackupDir   = /home/backup
  # see how the second argument relates to the first? [pause 3 seconds...] Good! Dora the Explorer appreciates you.

  # this variable is assigned to /home/compress/folder1/movieFile.mkv
  uncompressedVideoFileFullPath="$1"

  # basename is just the file name without the path: movieFile.mkv
  uncompressedVideoFile=$(basename "$1")

  # this substitution gets rid of the file extension, so we are left with /folder1/movieFile
  compressedVideoFileTitle="${2%.*}"

  # we know what basename does now, but this is only used for logging. Anyway, it would resolve to "movieFile"
  compressedVideoFileBase=$(basename "$compressedVideoFileTitle")

  # the MP4 container does not support Dolby Atmos or subtitle streams. Use a different preset if we are compressing to MP4
  if [ "$compressFileExt" = "$mkvFileExt" ]; then
    # run HandBrake: video - HQ 1080p, audio - surround passthrough,
    # AC-3 secondary stereo, backup codec: AC3

    # here's where it starts to suck! You know how we are compressing the file, but want to keep the same file name? Yeah,
    # we can't do that yet, because it would overwrite the uncompressed file. Instead, the output file is set to the file
    # extension $destinationTmpFormat (.hbtmp). Let's keep this example going with the first HandBrakeCLI command:

    # HandBrakeCLI --input '/home/compress/folder1/movieFile.mkv'
    #              --output '/home/compress' + '/folder1/movieFile' + '.hbtmp'
    #              --preset-import-file <this preset file is set at the top of the script>
    #                                   <it holds all of the necessary rules to compress the media>
    #              --preset 'HQ MKV'

    HandBrakeCLI --input "$uncompressedVideoFileFullPath" \
                 --output "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir/$MkvPresetFile" \
                 --preset "$MkvHqPreset" \;
  else
    HandBrakeCLI --input "$uncompressedVideoFileFullPath" \
                 --output "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" \
                 --preset-import-file "$PresetsDir/$Mp4PresetFile" \
                 --preset "$Mp4HqPreset" \;
  fi

  # make sure the HandBrake process finished successfully. Log the error if it didn't
  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile successfully finished compressing" >> "$LogFile"
  else
      echo "HandBrakeCLI did not exit with a return value of 0 while compressing $uncompressedVideoFile. Consider investigating?" >> "$ErrorFile"
  fi

  # create this directory if it doesn't exist yet, that's very important, otherwise the anal secretions will hit the fan...
  if [ ! -d "$FinishedDir" ]; then
      mkdir -p "$FinishedDir"
  fi

  # now we need to move the newly compressed file to the "finished" directory, and change the file extension back to what it once was
  # this move command keeps directory consistency so that the entire file structure looks the exact same, but with compressed files
     # '/home/compress' + '/folder1/movieFile' + '.hbtmp'          '/home/finished' + '/folder1/movieFile' + '.mkv'
  mv "$CompressDir$compressedVideoFileTitle$destinationTmpFormat" "$FinishedDir$compressedVideoFileTitle$compressFileExt"
  if [ $? -eq 0 ]; then
      echo "$compressedVideoFileBase$destinationTmpFormat is now located at $FinishedDir$compressedVideoFileTitle$compressFileExt"
  else
      echo "Could not move $compressedVideoFileBase$destinationTmpFormat to $FinishedDir$compressedVideoFileTitle$compressFileExt. Did HandBrakeCLI error out as well?" >> "$ErrorFile"
  fi

  if [ ! -d "$BackupDir" ]; then
      mkdir -p "$BackupDir"
  fi

  # this move command backs up the uncompressed media file, in case HandBrake messes up,
  # which happens fairly often, otherwise I'd just delete this file, but it's responsible not to
     # '/home/compress/folder1/movieFile.mkv' moves to '/home/backup'
  mv "$uncompressedVideoFileFullPath" "$BackupDir/"
  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile is now located in $BackupDir"
  else
      echo "Could not move $uncompressedVideoFile to $BackupDir. If this happens, the program may not have the required permissions!" >> "$ErrorFile"
  fi

  # Yay! it works! Congrats! That was awful!

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
    # this sed command creates the file path for everything beyond the compression directory.
    # for example, if the compression directory was /home/compress,
    # and the file path is /home/compress/folder1/movieFile,
    # the output of this command would result in: /folder1/movieFile
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

# delete all empty directories except the "compress" directory
find "$CompressDir" -mindepth 1 -type d -empty -delete

exit 0
