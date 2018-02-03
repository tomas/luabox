#!/bin/sh
set +e

CC=cc
name="luabox"

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
rm -f $name.o $name.a $name.so $name.os

luainc=$(pkg-config --cflags luajit)
# luainc="-I/usr/local/crew/include/luajit-2.0/"

$CC $CFLAGS $luainc -I termbox/src/ -o $name.o -c -Wall -Werror -fPIC $name.c

echo "Building $name.so (shared library)"
$CC -o $name.so -shared $name.o termbox/build/libtermbox.a
echo "Building $name.a (archive)"
ar rcs $name.a $name.o

echo "Done. Try running 'lua demos/simple.lua'"