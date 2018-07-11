#!/usr/bin/env make -f

NAME="luabox"
LUAINC = $(shell pkg-config --cflags luajit)
# LUAINC = -I/usr/local/crew/include/luajit-2.0/

# for layout demo
LUAJIT_INCLUDES = $(shell pkg-config --cflags --libs luajit)
CFLAGS = -g -lm -lrt -no-pie # -static
DEMO_DEPS = demos/lib/ui.lua demos/lib/classic.lua demos/lib/events.lua

all: luabox.a luabox.so

layout: luastatic luabox.a luabox.so
	@echo "Building layout"
	@luajit luastatic/luastatic.lua demos/layout.lua $(DEMO_DEPS) luabox.a libtermbox.a $(LUAJIT_INCLUDES) $(CFLAGS)
	# cc -Os -s demos/ui.lua.c $archives $flags $includes -o $out
	# @rm -f demos/$demo.lua.c

luastatic:
	@git clone https://github.com/ers35/luastatic

luabox.so: luabox.o
	@echo "Building $(NAME).a (archive)"
	@ar rcs $(NAME).a $(NAME).o

luabox.a: luabox.o libtermbox.a
	@echo "Building $(NAME).so (shared library)"
	@$(CC) -o $(NAME).so -shared $(NAME).o libtermbox.a

luabox.o: termbox
	@echo "Building layout.o"
	@$(CC) $(CFLAGS) $(LUAINC) -I termbox/src/ -c -Wall -Werror -fPIC $(NAME).c

libtermbox.a: termbox
	@mkdir -p termbox/build
	@cd termbox/build; cmake ..; make -j2
	@cp termbox/build/libtermbox.a .

termbox:
	@git clone https://github.com/tomas/termbox

.PHONY:clean
clean:
	rm -f $name.o $name.a $name.so $name.os
