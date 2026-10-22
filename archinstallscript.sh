#!/bin/bash

pfSize=$(cat /sys/firmware/efi/fw_platform_size)

if [ pfSize = "64" ]; then
  echo "this is 64"
else
  echo "this is not 64"
fi

