#!/bin/sh
############################################################################################################################################
# DESCRIPTION:     Video compression script that uses HandBrakeCLI for encoding: this version takes every .mkv larger than 14GB in the     #
#                  compressDirectory and compresses them. When completed, the script moves the uncompressed files into a backup directory  #
# ADDITIONAL INFO: Dependancies:                                                                                                           #
#                  - HandBrakeCLI (use latest build found at https://launchpad.net/~stebbins/+archive/ubuntu/handbrake-releases/+packages) #
#                  - lsof                                                                                                                  #
#                  - mediainfo                                                                                                             #
# AUTHOR:          Marcus Mueller                                                                                                          #
############################################################################################################################################

compressDirectory=/home/max/Max-Server-Files/odin\ server/Mitch
  backupDirectory=/home/max/Max-Server-Files/odin\ server/Backup_Raw_Movie_Files
    baseDirectory=/home/max/Max-Server-Files/odin\ server

  logFile="$baseDirectory/CompressionLog.txt"
errorFile="$baseDirectory/HandBrakeScriptErrorReport.txt"

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
    echo "Could not move $uncompressedVideoFile to $backupDirectory. If this happens, that means there is a bad bug that needs attention!" >> "$errorFile"
    exit 1
else
    echo "$uncompressedVideoFile is now located in $backupDirectory"
fi


done
