#!/bin/bash 
set -v -x #echo on

export DEVELOPER_DIR=/Applications/Xcode14_2.app/Contents/Developer

git pull
unset K2PROJ
which swift
swift package generate-xcodeproj
export K2PROJ=true
swift build -c release

echo "Removing old ik2gen..."
rm /opt/local/bin/ik2gen
chmod 755 ik2gen
cp ik2gen /opt/local/bin/
echo "Installation directory: $PWD"
sed -i '' "s|#_INSTALL_DIR_#|$PWD/|g" "/opt/local/bin/ik2gen"


echo Done
