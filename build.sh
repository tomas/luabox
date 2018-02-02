#!/bin/sh
set +e

CC=cc

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

echo "Cleaning up"
rm -f lua-termbox.o lua-termbox.a termbox.so

# luainc=$(pkg-config --cflags luajit)
luainc="-I/usr/local/crew/include/luajit-2.0/"

rm -f termbox.so lua-termbox.os
$CC $CFLAGS $luainc -I termbox/src/ -o lua-termbox.o -c -Wall -Werror -fPIC lua-termbox.c

echo "Building termbox.so (shared library)"
$CC -o termbox.so -shared lua-termbox.o termbox/build/libtermbox.a
echo "Building lua-termbox.a (archive)"
ar rcs lua-termbox.a lua-termbox.o

echo "Done. Try running 'lua demos/simple.lua'"