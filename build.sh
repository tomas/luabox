#!/bin/sh
set +e

GCC=gcc

if [ ! -d termbox ]; then
  echo "Please clone the termbox repo here: git clone https://github.com/tomas/termbox"
  exit 1
fi

# build termbox if we still haven't
if [ ! -e termbox/build/libtermbox.a ]; then
  cd termbox
  rm -Rf build
  mkdir build && cd build
  cmake ..
  make
  cd ../..
fi

rm -f termbox.so lua-termbox.os
$GCC $CFLAGS -I /usr/include/lua5.1 -I termbox/src/ -o lua-termbox.os -c -Wall -Werror -fPIC lua-termbox.c
$GCC -o termbox.so -shared lua-termbox.os termbox/build/libtermbox.a
