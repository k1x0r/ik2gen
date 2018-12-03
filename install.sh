#!/bin/bash

rm /usr/local/bin/ik1gen
chmod 755 ik1gen
cp ik1gen /usr/local/bin/
echo "Installation directory: $PWD"
sed -i '' "s|#_INSTALL_DIR_#|$PWD/|g" "/usr/local/bin/ik1gen"
echo Done
