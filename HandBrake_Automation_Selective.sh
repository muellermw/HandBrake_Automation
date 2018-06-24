#!/bin/sh

########################################################################################################################
# DESCRIPTION:     Video compression script that uses HandBrakeCLI for encoding: this version takes every .mkv file    #
#                  larger than "FileSizeLimit" GB in "CompressDir" and compresses it. When completed, the script       #
#                  moves the uncompressed file into a backup directory.                                                #
#                                                                                                                      #
# ADDITIONAL INFO: Dependancies:                                                                                       #
#                  - HandBrakeCLI (use latest build found at                                                           #
#                    https://launchpad.net/~stebbins/+archive/ubuntu/handbrake-releases/+packages)                     #
#                  - mediainfo                                                                                         #
#                                                                                                                      #
# AUTHOR:          Marcus Mueller                                                                                      #
########################################################################################################################

# TODO:
# Fill this information in for where the compression and backup should take place
CompressDir=
  BackupDir=

# in case we are using relative paths
CompressDir=$(realpath "$CompressDir")
  BackupDir=$(realpath "$BackupDir")

# the log files will be stored in the backup directory
  LogFile="$BackupDir/CompressionLoghbs.log"
ErrorFile="$BackupDir/HandBrakeScriptErrorReporthbs.log"

mkvFileExt=.mkv
mp4FileExt=.mp4

    AACCodec=aac
    AC3Codec=ac3
   EAC3Codec=eac3
DolbyHDCodec=truehd
    DTSCodec=dts
  DTSHDCodec=dtshd
    MP3Codec=mp3

AudioBitrate=448

# TODO:
# this script will only compress a movie file if it is larger than this size
FileSizeLimit=+14G

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

# this function will test the given file to see if it can be compressed by HandBrake
#   inputs:  the file path of the media file
#   outputs: 0 if file is valid, 1 if not
checkValidFile()
{
  # make sure HandBrake is not already running
  if (pgrep "HandBrakeCLI"); then
    echo "Existing HandBrakeCLI process detected: no need to start another compression"
    echo "Exiting..."
    return 1
  # make sure the file is not open before compressing it
  elif [ "$(lsof 2>/dev/null | grep "$1")" ]; then
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
#   inputs:  the file path of the media file, file base of the file
#   outputs: none
compressFile()
{
  uncompressedVideoFileFullPath="$1"
  uncompressedVideoFile=$(basename "$1")
  uncompressedVideoFileBase="$2"
  compressedVideoFileBase="${2%.*}$mp4FileExt"
  compressedVideoFile=$(basename "$compressedVideoFileBase")

  # Handbrake cannot encode Atmos/TrueHD 7.1 yet. If first stream is Atmos, grab the next available stream in hopes that it is AC3
  if [ ! "$(mediainfo "$uncompressedVideoFileFullPath" | grep -i A_TRUEHD)" ]; then
      # run HandBrake: video - HQ 1080p, audio - surround passthrough: AAC/AC-3/EAC-3/TrueHD/DTS/DTS-HD MA/MP3,
      # AC-3 secondary stereo, backup codec: MP3, bitrate: audioBitrate KB/s
      
      # the line: '-E copy,"$AC3Codec"' allows 2 audio tracks - one copied and one compressed - to coexist
      
      HandBrakeCLI -i "$CompressDir$uncompressedVideoFileBase" -o "$CompressDir$compressedVideoFileBase" \
      --preset="HQ 1080p30 Surround" \
      --audio-lang-list "eng" \     
      -E copy,"$AC3Codec" \
      --audio-copy-mask "$AACCodec","$AC3Codec","$EAC3Codec","$DolbyHDCodec","$DTSCodec","$DTSHDCodec","$MP3Codec" \
      -B $AudioBitrate \
      --audio-fallback "$MP3Codec" \
      --mixdown stereo \
      -A "Surround\ 7.1/5.1","Stereo"
  else
      echo "USING SECOND AUDIO STREAM!"
      echo "The second audio stream was chosen for $uncompressedVideoFile" >> "$LogFile"
      # run HandBrake: same settings but use second audio stream
      
      HandBrakeCLI -i "$CompressDir$uncompressedVideoFileBase" -o "$CompressDir$compressedVideoFileBase" \
      --preset="HQ 1080p30 Surround" \
      -a 2,2 \
      -E copy, "$AC3Codec" \
      --audio-copy-mask "$AACCodec","$AC3Codec","$EAC3Codec","$DolbyHDCodec","$DTSCodec","$DTSHDCodec","$MP3Codec" \
      -B $AudioBitrate \
      --audio-fallback "$MP3Codec" \
      --mixdown stereo \
      -A "Surround\ 7.1/5.1","Stereo"
  fi

  if [ $? -eq 0 ]; then
      echo "$uncompressedVideoFile was compressed to $compressedVideoFile" >> "$LogFile"
  else
      echo "HandBrakeCLI did not exit with a return value of 0 while compressing $uncompressedVideoFile. Consider investigating?" >> "$ErrorFile"
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

# this function walks through a directory tree and attempts to compress any valid files within it
# all files within the directory tree that are not valid are restored at the destination directory
#   inputs:  the file path of the directory to seach for compressable files
#   outputs: none
fileTreeWalker()
{
  for file in "$1"/*; do
    # create the new destination file base
    destFileBase=$(echo "$file" | sed "s|$CompressDir||")

    # this file is a directory
    if [ -d "$file" ]; then
	    # check if the directory is not empty, if so drill down into it
	    if ! checkEmptyDir "$file"; then
        fileTreeWalker "$file"
      fi
    # this is a regular file
    else
      # compare filename patterns with its basename
      case $(basename "$file") in
        $(basename "$0"))
          echo "$file is my own file, do not move or copy"
          ;;
        $(basename "$LogFile")|$(basename "$ErrorFile"))
          echo "$file is a program log file, do not move or copy"
          ;;
        *$mkvFileExt)
          echo "Found a movie file: " $(basename "$file")
          fullMovieFileName=$(realpath "$file")
          if checkValidFile "$fullMovieFileName"; then
            compressFile "$fullMovieFileName" "$destFileBase"
          fi
          ;;
      esac
    fi
  done
}


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

find "$CompressDir" -type d -empty -delete
