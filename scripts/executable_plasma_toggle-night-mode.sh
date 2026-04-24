#!/usr/bin/env bash

dbus-send --session --type=method_call \
  --dest=org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut string:"Toggle Night Color"