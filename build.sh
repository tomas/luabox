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

# -I/usr/local/include/luajit-2.0
luainc=$(pkg-config --cflags luajit)

rm -f termbox.so lua-termbox.os
$GCC $CFLAGS $luainc -I termbox/src/ -o lua-termbox.o -c -Wall -Werror -fPIC lua-termbox.c

echo "Building termbox.so (shared library)"
$GCC -o termbox.so -shared lua-termbox.o termbox/build/libtermbox.a
echo "Building lua-termbox.a (archive)"
ar rcs lua-termbox.a lua-termbox.o