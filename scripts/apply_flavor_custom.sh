#!/bin/bash
if [ ! -d "scripts" ]; then
  cd ..
fi

./flutterw clean

cp flavors/pubspec_custom.lock pubspec.lock
cp flavors/pubspec_custom.yaml pubspec.yaml

./flutterw pub get --enforce-lockfile
