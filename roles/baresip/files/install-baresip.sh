#!/bin/bash

set -ex


main() {
  cd "$(mktemp -d)"

  install_re
  install_baresip
}

install_re() {
  git clone --depth=1 https://github.com/baresip/re
  cd re

  cmake -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j
  cmake --install build
  ldconfig

  cd ../
}

install_baresip() {
  git clone --depth=1 https://github.com/baresip/baresip
  cd baresip

  cmake -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j
  cmake --install build
  ldconfig

  cd ../
}


log_file=/var/log/baresip-install.log

date >> "$log_file"
main | tee -a "$log_file"
echo "[$(date)] Done" >> "$log_file"
