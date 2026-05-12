#!/usr/bin/env make -f

NAME="luabox"

# LuaJIT for static archive (.a) — local source when available
ifneq ($(wildcard ../luajit),)
  LUAJIT_ARC   = "../luajit/src/luajit"
  LUAINC_ARC   = "-I../luajit/src"
  LUAJIT_LIB   = "-L../luajit/src"
  LUAJIT_ARCHIVE = "../luajit/src/libluajit.a"
else
  LUAJIT_ARC   = "luajit"
  LUAINC_ARC   = $(shell pkg-config --cflags luajit)
  LUAJIT_LIB   = $(shell pkg-config --libs-only-L luajit)
  LUAJIT_ARCHIVE = $(shell pkg-config --libs luajit | sed 's/-l/-l:lib/g; s/ / lib/g')
endif

# LuaJIT for shared library (.so) — always the system's version
LUAINC_SYS   = $(shell pkg-config --cflags luajit)
LUAJIT_LIBS  = $(shell pkg-config --libs luajit)

DEMO_DEPS = demos/lib/ui.lua demos/lib/classic.lua demos/lib/events.lua

all: luabox.a luabox.so

layout: luastatic luabox.a luabox.so
	@echo "Building layout"
	@$(LUAJIT_ARC) luastatic/luastatic.lua demos/layout.lua $(DEMO_DEPS) \
	  luabox.a libtermbox.a $(LUAINC_ARC) $(LUAJIT_ARCHIVE) $(CFLAGS)

luastatic:
	@git clone https://github.com/ers35/luastatic

# Static archive uses local LuaJIT 2.0.5 (when ../luajit exists)
luabox.a: luabox_arc.o
	@echo "Building $(NAME).a (archive)"
	@ar rcs $(NAME).a luabox_arc.o

luabox_arc.o: termbox
	@echo "Building luabox_arc.o (static archive, local Luajit)"
	@$(CC) $(CFLAGS) $(LUAINC_ARC) -I termbox/src/ -c -Wall -Werror -fPIC \
	  $(NAME).c -o $@

# Shared library uses system LuaJIT 2.1
luabox.so: luabox_shr.o libtermbox.a
	@echo "Building $(NAME).so (shared library, system Luajit)"
	@$(CC) -o $(NAME).so -shared luabox_shr.o libtermbox.a $(LUAJIT_LIBS)

luabox_shr.o: termbox
	@echo "Building luabox_shr.o (shared library, system Luajit)"
	@$(CC) $(CFLAGS) $(LUAINC_SYS) -I termbox/src/ -c -Wall -Werror -fPIC \
	  $(NAME).c -o $@

libtermbox.a: termbox
	@mkdir -p termbox/build
	@cd termbox/build; cmake .. -DBUILD_SHARED_LIBS=OFF; make -j2
	@cp termbox/build/libtermbox.a .

termbox:
	@git clone https://github.com/tomas/termbox

.PHONY:clean
clean:
	rm -f *.o *.a *.so *.os
