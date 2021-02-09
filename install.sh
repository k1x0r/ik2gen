#!/bin/bash 
set -v -x #echo on

swift build --target ik2proj -c release
swift package generate-xcodeproj

echo "Removing old ik2gen..."
rm /usr/local/bin/ik2gen
chmod 755 ik2gen
cp ik2gen /usr/local/bin/
echo "Installation directory: $PWD"
sed -i '' "s|#_INSTALL_DIR_#|$PWD/|g" "/usr/local/bin/ik2gen"


echo Done
