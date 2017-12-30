#!/bin/sh
############################################################################################################################################
# DESCRIPTION:     Video compression script that uses HandBrakeCLI for encoding: this version takes every .mkv larger than 14GB in the     #
#                  compressDirectory and compresses them. When completed, the script moves the uncompressed files into a backup directory  #
#                  Arguments:                                                                                                              #
#                            1 - directory of files to compress                                                                            #
#                            2 - directory to store backup uncompressed files                                                              #
#                            3 - (OPTIONAL) directory to put log files                                                                     #
# ADDITIONAL INFO: Dependancies:                                                                                                           #
#                  - HandBrakeCLI (use latest build found at https://launchpad.net/~stebbins/+archive/ubuntu/handbrake-releases/+packages) #
#                  - realpath                                                                                                              #
#                  - lsof                                                                                                                  #
#                  - mediainfo                                                                                                             #
# AUTHOR:          Marcus Mueller                                                                                                          #
############################################################################################################################################

HELP="Usage:\n \
      \thandbrakeScript.sh [directory of files to compress] [directory to store backup uncompressed files] [(OPTIONAL) directory to put logs]\n \
      \thandbrakeScript.sh --help (gives this usage message)\n \
      \tThe log directory defaults to ~/Desktop \
     "

if [ -z "$1" ]; then
    echo "No compression directory supplied"
    echo $HELP
    exit 1
elif [ "$1" = "--help" ] || [ "$1" = "-help" ] || [ "$1" = "help" ]; then
    echo $HELP
    exit 0
elif [ ! -d "$1" ]; then
    echo "Could not find directory $1: does not exist"
    echo $HELP
    exit 1
else
    compressDirectory=$(realpath "$1")
fi

if [ -z "$2" ]; then
    echo "No backup directory supplied"
    echo $HELP
    exit 1
elif [ ! -d "$2" ]; then
    echo "Could not find directory $2: does not exist"
    echo $HELP
    exit 1
elif [ "$1" = "$2" ]; then
    echo "The compress directory and backup directory cannot be the same!"
    exit 1
else
    backupDirectory=$(realpath "$2")
fi

if [ -z "$3" ]; then
    logDirectory=~/Desktop
elif [ ! -d "$3" ]; then
    echo "Could not find directory $3: does not exist"
    echo $HELP
    exit 1
else
    logDirectory=$(realpath "$3")
fi

echo "Compress directory: $compressDirectory"
echo "Backup directory: $backupDirectory"
echo "Log directory: $logDirectory"

  logFile="$logDirectory/CompressionLog.txt"
errorFile="$logDirectory/HandBrakeScriptErrorReport.txt"

mkvFileExt=.mkv
mp4FileExt=.mp4

    AACCodec=aac
    AC3Codec=ac3
   EAC3Codec=eac3
DolbyHDCodec=truehd
    DTSCodec=dts
  DTSHDCodec=dtshd
    MP3Codec=mp3

audioBitrate=448


while true; do

# wait 3 seconds so the previous process can gracefully close
sleep 3

if (pgrep "HandBrakeCLI"); then
    echo "Existing HandBrakeCLI process detected: no need to start another compression"
    echo "Exiting..."
    exit 0
fi

# check for .mkv files that are larger than 15GB
mkvFile=$(find "$compressDirectory" -name "*$mkvFileExt" -size +14G | head -n 1)

if [ "x$mkvFile" != "x" ]; then
    uncompressedVideoFile=$(basename "$mkvFile")
    uncompressedVideoFileFullPath="$mkvFile"
    compressedVideoFile=${uncompressedVideoFile%.*}$mp4FileExt
    echo "$mkvFileExt file found: $uncompressedVideoFile"
else
    echo "No more files found"
    echo "Exiting..."
    exit 0
fi

# make sure the file is not open before compressing it
while :
do
    if [ ! "$(lsof 2>/dev/null | grep "$uncompressedVideoFileFullPath")" ]; then
        break
    fi
    sleep 1
done
echo "$uncompressedVideoFile is not open. We are ready to compress..."

# Handbrake cannot encode Atmos/TrueHD 7.1 yet. If first stream is Atmos, grab the next available stream in hopes that it is AC3
if [ ! "$(mediainfo "$uncompressedVideoFileFullPath" | grep -i A_TRUEHD)" ]; then
    # run handbrake: video - HQ 1080p, audio - surround passthrough: AAC/AC-3/EAC-3/TrueHD/DTS/DTS-HD MA/MP3, AC-3 secondary stereo, backup codec: MP3, bitrate: audioBitrate KB/s
    HandBrakeCLI -i "$compressDirectory/$uncompressedVideoFile" -o "$compressDirectory/$compressedVideoFile" --preset="HQ 1080p30 Surround" --audio-lang-list "eng" -E copy,"$AC3Codec" --audio-copy-mask "$AACCodec","$AC3Codec","$EAC3Codec","$DolbyHDCodec","$DTSCodec","$DTSHDCodec","$MP3Codec" -B $audioBitrate --audio-fallback "$MP3Codec" --mixdown stereo -A "Surround\ 7.1/5.1","Stereo"
else
    echo "USING SECOND AUDIO STREAM!"
    # run handbrake: same settings but use second audio stream
    HandBrakeCLI -i "$compressDirectory/$uncompressedVideoFile" -o "$compressDirectory/$compressedVideoFile" --preset="HQ 1080p30 Surround" -a 2,2 -E copy,"$AC3Codec" --audio-copy-mask "$AACCodec","$AC3Codec","$EAC3Codec","$DolbyHDCodec","$DTSCodec","$DTSHDCodec","$MP3Codec" -B $audioBitrate --audio-fallback "$MP3Codec" --mixdown stereo -A "Surround\ 7.1/5.1","Stereo"
fi

if [ $? -ne 0 ]; then
    echo "HandBrakeCLI did not exit with a return value of 0 while compressing $uncompressedVideoFile. Consider investigating?" >> "$errorFile"
else
    echo "$uncompressedVideoFile was compressed to $compressedVideoFile" >> "$logFile"
fi

if [ ! -d "$backupDirectory" ]; then
    mkdir "$backupDirectory"
fi

mv "$uncompressedVideoFileFullPath" "$backupDirectory/"
if [ $? -ne 0 ]; then
    echo "Could not move $uncompressedVideoFile to $backupDirectory. If this happens, the program may be in an infinite loop!" >> "$errorFile"
    exit 1
else
    echo "$uncompressedVideoFile is now located in $backupDirectory"
fi


done
