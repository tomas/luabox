#!/usr/bin/env make -f

NAME="luabox"
# CFLAGS = -g -lm -lrt # -static

# if parent dir contains a luajix dir, then use it
ifneq ($(wildcard ../luajit),)
	LUAJIT = "../luajit/src/luajit"
	LUAINC = "-I../luajit/src"
	LUAJIT_LIB_PATH="-L../luajit/src"
	LUAJIT_ARCHIVE="../luajit/src/libluajit.a"
else
	LUAJIT = "luajit"
	LUAINC = $(shell pkg-config --cflags luajit)
	LUAJIT_LIB_PATH = $(shell pkg-config --libs-only-L luajit)
endif

# LUAINC = "-I/data/data/com.termux/files/usr/include/luajit-2.0"
# LUAINC = -I/usr/local/crew/include/luajit-2.0/

DEMO_DEPS = demos/lib/ui.lua demos/lib/classic.lua demos/lib/events.lua

all: luabox.a luabox.so

layout: luastatic luabox.a luabox.so
	@echo "Building layout"
	@$(LUAJIT) luastatic/luastatic.lua demos/layout.lua $(DEMO_DEPS) luabox.a libtermbox.a $(LUAINC) $(LUAJIT_ARCHIVE) $(CFLAGS)
	# cc -Os -s demos/ui.lua.c $archives $flags $includes -o $out
	# @rm -f demos/$demo.lua.c

luastatic:
	@git clone https://github.com/ers35/luastatic

luabox.a: luabox.o
	@echo "Building $(NAME).a (archive)"
	@ar rcs $(NAME).a $(NAME).o

luabox.so: luabox.o libtermbox.a
	@echo "Building $(NAME).so (shared library)"
	@$(CC) -o $(NAME).so -shared $(NAME).o $(LUAJIT_LIB_PATH) -lluajit libtermbox.a

.PHONY:luabox.o
luabox.o: termbox
	@echo "Building luabox.o"
	@$(CC) $(CFLAGS) $(LUAINC) -I termbox/src/ -c -Wall -Werror -fPIC $(NAME).c

libtermbox.a: termbox
	@mkdir -p termbox/build
	@cd termbox/build; cmake .. -DBUILD_SHARED_LIBS=OFF; make -j2
	@cp termbox/build/libtermbox.a .

termbox:
	@git clone https://github.com/tomas/termbox

.PHONY:clean
clean:
	rm -f $name.o $name.a $name.so $name.os
