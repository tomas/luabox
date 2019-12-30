#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h> // malloc, free
#include <string.h> // strlen, strncpy
#include <termbox.h>
#include "util.h"

static int char_len;
static char utf8_char[5];

#if defined(LUA_VERSION_NUM) && LUA_VERSION_NUM == 501

#if !defined(luaL_newlibtable) // detect if luajit >= 2.1
  LUALIB_API void luaL_setfuncs(lua_State *L, const luaL_Reg *l, int nup) {
    // luaL_checkversion(L);
    luaL_checkstack(L, nup, "too many upvalues");
    for (; l->name != NULL; l++) {
      int i;
      for (i = 0; i < nup; i++)
        lua_pushvalue(L, -nup);
      lua_pushcclosure(L, l->func, nup);
      lua_setfield(L, -(nup + 2), l->name);
    }
    lua_pop(L, nup);
  }

  #define luaL_newlibtable(L,l)       lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)
  #define luaL_newlib(L,l)            (luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))
#endif

  #define luaL_checkunsigned(L, narg) (luaL_checknumber(L, narg))
  #define luaL_len(L, idx)            (lua_objlen(L, idx))

#elif defined(LUA_VERSION_NUM) && LUA_VERSION_NUM == 503
  #define luaL_checkunsigned(L, narg) (luaL_checknumber(L, narg))
#endif

static struct tb_event event;

static int l_tb_init(lua_State *L) {
  lua_pushinteger(L, tb_init());
  return 1;
}

static int l_tb_init_with(lua_State *L) {
  uint16_t flags = luaL_checkunsigned(L, 1);
  lua_pushinteger(L, tb_init_with(flags));
  return 1;
}

static int l_tb_shutdown(lua_State *L) {
  tb_shutdown();
  return 0;
}

static int l_tb_width(lua_State *L) {
  lua_pushinteger(L, tb_width());
  return 1;
}

static int l_tb_height(lua_State *L) {
  lua_pushinteger(L, tb_height());
  return 1;
}

static int l_tb_clear_screen(lua_State *L) {
  tb_clear_screen();
  return 0;
}

static int l_tb_clear_buffer(lua_State *L) {
  tb_clear_buffer();
  return 0;
}

static int l_tb_set_clear_attributes(lua_State *L) {
  uint16_t fg = luaL_checkunsigned(L, 1);
  uint16_t bg = luaL_checkunsigned(L, 2);

  lua_pop(L, 2);
  tb_set_clear_attributes(fg, bg);
  return 0;
}

static int l_tb_resize(lua_State *L) {
  tb_resize();
  return 0;
}

static int l_tb_render(lua_State *L) {
  tb_render();
  return 0;
}

static int l_tb_set_cursor(lua_State *L) {
  int cx = luaL_checkinteger(L, 1);
  int cy = luaL_checkinteger(L, 2);

  lua_pop(L, 2);
  tb_set_cursor(cx, cy);
  return 0;
}

static int l_tb_show_cursor(lua_State *L) {
  tb_show_cursor();
  return 0;
}

static int l_tb_hide_cursor(lua_State *L) {
  tb_hide_cursor();
  return 0;
}

static int l_tb_cell(lua_State *L) {
  int x = luaL_checkinteger(L, 1);
  int y = luaL_checkinteger(L, 2);
  luaL_checktype(L, 3, LUA_TTABLE);

/* TODO: allow less than 3 members by default values */
  lua_getfield(L, 3, "ch");
  lua_getfield(L, 3, "fg");
  lua_getfield(L, 3, "bg");

  const struct tb_cell cell = {
    .ch = luaL_checkstring(L, -3)[0],
    .fg = luaL_checkinteger(L, -2),
    .bg = luaL_checkinteger(L, -1),
  };

  lua_pop(L, 6);
  tb_cell(x, y, &cell);
  return 0;
}

static uint32_t normalize_char(const char * str) {
  uint32_t ch;

  // str might be a number (char code), a unicode string or an actual char
  // we'll start checking with the most probable scenario: a regular char
  if (!str[1]) {
    ch = str[0];
  } else if (str[1] >= '0' && str[1] <= '9') { // looks like a number
    ch = atoi(str);
  } else {
    tb_utf8_char_to_unicode(&ch, str);
  }

  return ch;
}

static int l_tb_char(lua_State* L) {
  int x       = luaL_checkinteger(L, 1);
  int y       = luaL_checkinteger(L, 2);
  uint16_t fg = luaL_checkunsigned(L, 3);
  uint16_t bg = luaL_checkunsigned(L, 4);
  const char * str = luaL_checkstring(L, 5);

  uint32_t ch = normalize_char(str);
  tb_char(x, y, fg, bg, ch);

  lua_pop(L, 5);
  return 0;
}

static int l_tb_string(lua_State *L) {
  int x = luaL_checkinteger(L, 1);
  int y = luaL_checkinteger(L, 2);
  int fg = luaL_checkinteger(L, 3);
  int bg = luaL_checkinteger(L, 4);
  const char * str = luaL_checkstring(L, 5);

  int len;
  if (lua_gettop(L) == 6) {
    len = tb_string_with_limit(x, y, fg, bg, (char *)str, luaL_checkinteger(L, 6));
  } else {
    len = tb_string(x, y, fg, bg, (char *)str);
  }

  lua_pushinteger(L, len);
  return 1;
}

static int l_tb_stringf(lua_State *L) {
  int x = luaL_checkinteger(L, 1);
  int y = luaL_checkinteger(L, 2);
  int fg = luaL_checkinteger(L, 3);
  int bg = luaL_checkinteger(L, 4);
  const char * fmt = luaL_checkstring(L, 5);

  int buflen = strlen(fmt);   // initial buffer length
  int total  = lua_gettop(L); // total arguments passed
  int remain = total - 5;     // remaning arguments in stack

  char * arr[remain];
  // char ** arr = calloc(remain, sizeof(char *));

  int i = remain;
  while (i--) {
    arr[i] = (char *)luaL_checkstring(L, 6 + i);
    buflen += strlen(arr[i]);
  }

  char final[buflen * 2];
  arsprintf(final, fmt, arr);

  int len = tb_string(x, y, fg, bg, final);
  lua_pushinteger(L, len);

  return 1;
}

static int l_tb_enable_mouse(lua_State *L) {
  tb_enable_mouse();
  return 0;
}

static int l_tb_disable_mouse(lua_State *L) {
  tb_disable_mouse();
  return 0;
}

static int l_tb_select_output_mode(lua_State *L) {
  int mode = luaL_checkinteger(L, 1);

  lua_pop(L, 1);
  lua_pushinteger(L, tb_select_output_mode(mode));
  return 1;
}

void populate_event(lua_State *L) {
  lua_pushnumber(L, event.type);
  lua_setfield(L, 1, "type");

  lua_pushnumber(L, event.key);
  lua_setfield(L, 1, "key");

  lua_pushnumber(L, event.meta);
  lua_setfield(L, 1, "meta"); // ctrl/alt/shift or motion in mouse events

  if (event.type == TB_EVENT_MOUSE) {

    lua_pushnumber(L, event.x);
    lua_setfield(L, 1, "x");

    lua_pushnumber(L, event.y);
    lua_setfield(L, 1, "y");

    lua_pushnumber(L, event.h);
    lua_setfield(L, 1, "clicks"); // click count

  } else if (event.type == TB_EVENT_KEY) {

    char_len = tb_utf8_unicode_to_char(utf8_char, event.ch);
    utf8_char[char_len] = '\0';

    lua_pushstring(L, utf8_char);
    lua_setfield(L, 1, "ch");

  } else if (event.type == TB_EVENT_RESIZE) {
    lua_pushnumber(L, event.w);
    lua_setfield(L, 1, "w");

    lua_pushnumber(L, event.h);
    lua_setfield(L, 1, "h");
  }
}

static int l_tb_peek_event(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  int timeout = luaL_checkinteger(L, 2);

  int ret = tb_peek_event(&event, timeout);
  populate_event(L);

  lua_pop(L, 2);
  lua_pushinteger(L, ret);
  return 1;
}

static int l_tb_poll_event(lua_State *L){
  luaL_checktype(L, 1, LUA_TTABLE);

  int ret = tb_poll_event(&event);
  populate_event(L);

  lua_pop(L, 1);
  lua_pushinteger(L, ret);
  return 1;
}

static int l_tb_utf8_char_length(lua_State *L) {
  char c = luaL_checkstring(L, 1)[0];

  lua_pop(L, 1);
  lua_pushinteger(L, tb_utf8_char_length(c));
  return 1;
}

static int l_tb_utf8_char_to_unicode(lua_State *L) {
  const char * str = luaL_checkstring(L, 1);
  uint32_t ch = normalize_char(str);
  lua_pop(L, 1);
  lua_pushinteger(L, ch);
  return 1;
}

static int l_tb_utf8_unicode_to_char(lua_State *L) {
  const char * str = luaL_checkstring(L, 1);

  uint32_t ch = normalize_char(str);
  char *out = NULL;

  lua_pop(L, 1);
  lua_pushinteger(L, tb_utf8_unicode_to_char(out, ch));
  return 1;
}

static int l_tb_is_char_wide(lua_State *L) {
  const char * str = luaL_checkstring(L, 1);
  uint32_t ch = normalize_char(str);

  lua_pop(L, 1);
  lua_pushinteger(L, tb_unicode_is_char_wide(ch));
  return 1;
}

///////////////////
// helpers

static int l_tb_rgb(lua_State *L) {
  uint32_t col = luaL_checkunsigned(L, 1);
  lua_pushinteger(L, tb_rgb(col));
  return 1;
}

static int l_tb_bold(lua_State *L) {
  uint16_t col = luaL_checkunsigned(L, 1);
  lua_pushinteger(L, col | TB_BOLD);
  return 1;
}

static int l_tb_underline(lua_State *L) {
  uint16_t col = luaL_checkunsigned(L, 1);
  lua_pushinteger(L, col | TB_UNDERLINE);
  return 1;
}

static const struct luaL_Reg l_luabox[] = {
  {"init",                   l_tb_init},
  {"init_with",              l_tb_init_with},
  {"shutdown",               l_tb_shutdown},
  {"width",                  l_tb_width},
  {"height",                 l_tb_height},
  {"clear_screen",           l_tb_clear_screen},
  {"clear_buffer",           l_tb_clear_buffer},
  {"set_clear_attributes",   l_tb_set_clear_attributes},
  {"resize",                 l_tb_resize},
  {"render",                 l_tb_render},
  {"rgb",                    l_tb_rgb},
  {"bold",                   l_tb_bold},
  {"underline",              l_tb_underline},
  {"cell",                   l_tb_cell},
  {"char",                   l_tb_char},
  {"string",                 l_tb_string},
  {"stringf",                l_tb_stringf},
  {"set_cursor",             l_tb_set_cursor},
  {"show_cursor",            l_tb_show_cursor},
  {"hide_cursor",            l_tb_hide_cursor},
  {"enable_mouse",           l_tb_enable_mouse},
  {"disable_mouse",          l_tb_disable_mouse},
  {"select_output_mode",     l_tb_select_output_mode},
  {"peek_event",             l_tb_peek_event},
  {"poll_event",             l_tb_poll_event},
  {"utf8_char_length",       l_tb_utf8_char_length},
  {"utf8_char_to_unicode",   l_tb_utf8_char_to_unicode},
  {"utf8_unicode_to_char",   l_tb_utf8_unicode_to_char},
  {"is_char_wide",           l_tb_is_char_wide},
  {NULL,NULL}
};

int luaopen_luabox(lua_State *L) {
  luaL_newlib(L, l_luabox);

  // init options
  lua_pushnumber(L, TB_INIT_ALL          ); lua_setfield(L, -2, "INIT_ALL");
  lua_pushnumber(L, TB_INIT_ALTSCREEN    ); lua_setfield(L, -2, "INIT_ALTSCREEN");
  lua_pushnumber(L, TB_INIT_KEYPAD       ); lua_setfield(L, -2, "INIT_KEYPAD");
  lua_pushnumber(L, TB_INIT_NO_CURSOR    ); lua_setfield(L, -2, "INIT_NO_CURSOR");
  lua_pushnumber(L, TB_INIT_DETECT_MODE  ); lua_setfield(L, -2, "INIT_DETECT_MODE");

  // output modes
  lua_pushnumber(L, TB_OUTPUT_NORMAL); lua_setfield(L, -2, "OUTPUT_NORMAL");
  lua_pushnumber(L, TB_OUTPUT_256);    lua_setfield(L, -2, "OUTPUT_256");
  #ifdef WITH_TRUECOLOR
  lua_pushnumber(L, TB_OUTPUT_TRUECOLOR); lua_setfield(L, -2, "OUTPUT_TRUECOLOR");
  #endif

  // errors
  lua_pushnumber(L, TB_EUNSUPPORTED_TERMINAL); lua_setfield(L, -2, "EUNSUPPORTED_TERMINAL");
  lua_pushnumber(L, TB_EFAILED_TO_OPEN_TTY  ); lua_setfield(L, -2, "EFAILED_TO_OPEN_TTY");
  lua_pushnumber(L, TB_EPIPE_TRAP_ERROR     ); lua_setfield(L, -2, "EPIPE_TRAP_ERROR");

  // event types
  lua_pushnumber(L, TB_EVENT_KEY    ); lua_setfield(L, -2, "EVENT_KEY");
  lua_pushnumber(L, TB_EVENT_RESIZE ); lua_setfield(L, -2, "EVENT_RESIZE");
  lua_pushnumber(L, TB_EVENT_MOUSE  ); lua_setfield(L, -2, "EVENT_MOUSE");

  // text attributes
  lua_pushnumber(L, TB_BOLD         ); lua_setfield(L, -2, "BOLD");
  lua_pushnumber(L, TB_UNDERLINE    ); lua_setfield(L, -2, "UNDERLINE");
  lua_pushnumber(L, TB_REVERSE      ); lua_setfield(L, -2, "REVERSE");

  // colors
  lua_pushnumber(L, TB_DEFAULT       ); lua_setfield(L, -2, "DEFAULT");
  lua_pushnumber(L, TB_RED           ); lua_setfield(L, -2, "RED");
  lua_pushnumber(L, TB_GREEN         ); lua_setfield(L, -2, "GREEN");
  lua_pushnumber(L, TB_YELLOW        ); lua_setfield(L, -2, "YELLOW");
  lua_pushnumber(L, TB_BLUE          ); lua_setfield(L, -2, "BLUE");
  lua_pushnumber(L, TB_MAGENTA       ); lua_setfield(L, -2, "MAGENTA");
  lua_pushnumber(L, TB_CYAN          ); lua_setfield(L, -2, "CYAN");
  lua_pushnumber(L, TB_LIGHT_GRAY    ); lua_setfield(L, -2, "LIGHT_GRAY");
  lua_pushnumber(L, TB_MEDIUM_GRAY   ); lua_setfield(L, -2, "MEDIUM_GRAY");
  lua_pushnumber(L, TB_GRAY          ); lua_setfield(L, -2, "GRAY");
  lua_pushnumber(L, TB_LIGHT_RED     ); lua_setfield(L, -2, "LIGHT_RED");
  lua_pushnumber(L, TB_LIGHT_GREEN   ); lua_setfield(L, -2, "LIGHT_GREEN");
  lua_pushnumber(L, TB_LIGHT_YELLOW  ); lua_setfield(L, -2, "LIGHT_YELLOW");
  lua_pushnumber(L, TB_LIGHT_BLUE    ); lua_setfield(L, -2, "LIGHT_BLUE");
  lua_pushnumber(L, TB_LIGHT_MAGENTA ); lua_setfield(L, -2, "LIGHT_MAGENTA");
  lua_pushnumber(L, TB_LIGHT_CYAN    ); lua_setfield(L, -2, "LIGHT_CYAN");
  lua_pushnumber(L, TB_WHITE         ); lua_setfield(L, -2, "WHITE");
  lua_pushnumber(L, TB_BLACK         ); lua_setfield(L, -2, "BLACK");

  lua_pushnumber(L, TB_DARKEST_GRAY   ); lua_setfield(L, -2, "DARKEST_GRAY");
  lua_pushnumber(L, TB_DARKER_GRAY    ); lua_setfield(L, -2, "DARKER_GRAY");
  lua_pushnumber(L, TB_DARK_GRAY      ); lua_setfield(L, -2, "DARK_GRAY");
  lua_pushnumber(L, TB_LIGHTER_GRAY   ); lua_setfield(L, -2, "LIGHTER_GRAY");
  lua_pushnumber(L, TB_LIGHTEST_GRAY  ); lua_setfield(L, -2, "LIGHTEST_GRAY");

  lua_pushnumber(L, TB_NONE           ); lua_setfield(L, -2, "NONE");
  lua_pushnumber(L, TB_DARKEST_GREY   ); lua_setfield(L, -2, "DARKEST_GREY");
  lua_pushnumber(L, TB_DARKER_GREY    ); lua_setfield(L, -2, "DARKER_GREY");
  lua_pushnumber(L, TB_DARK_GREY      ); lua_setfield(L, -2, "DARK_GREY");
  lua_pushnumber(L, TB_MEDIUM_GREY    ); lua_setfield(L, -2, "MEDIUM_GREY");
  lua_pushnumber(L, TB_GREY           ); lua_setfield(L, -2, "GREY");
  lua_pushnumber(L, TB_LIGHT_GREY     ); lua_setfield(L, -2, "LIGHT_GREY");
  lua_pushnumber(L, TB_LIGHTER_GREY   ); lua_setfield(L, -2, "LIGHTER_GREY");
  lua_pushnumber(L, TB_LIGHTEST_GREY  ); lua_setfield(L, -2, "LIGHTEST_GREY");

  // keys
  lua_pushnumber(L, TB_KEY_F1               ); lua_setfield(L, -2, "KEY_F1");
  lua_pushnumber(L, TB_KEY_F2               ); lua_setfield(L, -2, "KEY_F2");
  lua_pushnumber(L, TB_KEY_F3               ); lua_setfield(L, -2, "KEY_F3");
  lua_pushnumber(L, TB_KEY_F4               ); lua_setfield(L, -2, "KEY_F4");
  lua_pushnumber(L, TB_KEY_F5               ); lua_setfield(L, -2, "KEY_F5");
  lua_pushnumber(L, TB_KEY_F6               ); lua_setfield(L, -2, "KEY_F6");
  lua_pushnumber(L, TB_KEY_F7               ); lua_setfield(L, -2, "KEY_F7");
  lua_pushnumber(L, TB_KEY_F8               ); lua_setfield(L, -2, "KEY_F8");
  lua_pushnumber(L, TB_KEY_F9               ); lua_setfield(L, -2, "KEY_F9");
  lua_pushnumber(L, TB_KEY_F10              ); lua_setfield(L, -2, "KEY_F10");
  lua_pushnumber(L, TB_KEY_F11              ); lua_setfield(L, -2, "KEY_F11");
  lua_pushnumber(L, TB_KEY_F12              ); lua_setfield(L, -2, "KEY_F12");
  lua_pushnumber(L, TB_KEY_INSERT           ); lua_setfield(L, -2, "KEY_INSERT");
  lua_pushnumber(L, TB_KEY_DELETE           ); lua_setfield(L, -2, "KEY_DELETE");
  lua_pushnumber(L, TB_KEY_HOME             ); lua_setfield(L, -2, "KEY_HOME");
  lua_pushnumber(L, TB_KEY_END              ); lua_setfield(L, -2, "KEY_END");
  lua_pushnumber(L, TB_KEY_PGUP             ); lua_setfield(L, -2, "KEY_PGUP");
  lua_pushnumber(L, TB_KEY_PGDN             ); lua_setfield(L, -2, "KEY_PGDN");
  lua_pushnumber(L, TB_KEY_PAGE_UP          ); lua_setfield(L, -2, "KEY_PAGE_UP");
  lua_pushnumber(L, TB_KEY_PAGE_DOWN        ); lua_setfield(L, -2, "KEY_PAGE_DOWN");

  lua_pushnumber(L, TB_KEY_ARROW_LEFT       ); lua_setfield(L, -2, "KEY_ARROW_LEFT");
  lua_pushnumber(L, TB_KEY_ARROW_RIGHT      ); lua_setfield(L, -2, "KEY_ARROW_RIGHT");
  lua_pushnumber(L, TB_KEY_ARROW_DOWN       ); lua_setfield(L, -2, "KEY_ARROW_DOWN");
  lua_pushnumber(L, TB_KEY_ARROW_UP         ); lua_setfield(L, -2, "KEY_ARROW_UP");

  lua_pushnumber(L, TB_KEY_MOUSE_LEFT       ); lua_setfield(L, -2, "KEY_MOUSE_LEFT");
  lua_pushnumber(L, TB_KEY_MOUSE_RIGHT      ); lua_setfield(L, -2, "KEY_MOUSE_RIGHT");
  lua_pushnumber(L, TB_KEY_MOUSE_MIDDLE     ); lua_setfield(L, -2, "KEY_MOUSE_MIDDLE");
  lua_pushnumber(L, TB_KEY_MOUSE_RELEASE    ); lua_setfield(L, -2, "KEY_MOUSE_RELEASE");
  lua_pushnumber(L, TB_KEY_MOUSE_WHEEL_UP   ); lua_setfield(L, -2, "KEY_MOUSE_WHEEL_UP");
  lua_pushnumber(L, TB_KEY_MOUSE_WHEEL_DOWN ); lua_setfield(L, -2, "KEY_MOUSE_WHEEL_DOWN");

  lua_pushnumber(L, TB_KEY_CTRL_TILDE       ); lua_setfield(L, -2, "KEY_CTRL_TILDE");
  lua_pushnumber(L, TB_KEY_CTRL_2           ); lua_setfield(L, -2, "KEY_CTRL_2");
  lua_pushnumber(L, TB_KEY_CTRL_A           ); lua_setfield(L, -2, "KEY_CTRL_A");
  lua_pushnumber(L, TB_KEY_CTRL_B           ); lua_setfield(L, -2, "KEY_CTRL_B");
  lua_pushnumber(L, TB_KEY_CTRL_C           ); lua_setfield(L, -2, "KEY_CTRL_C");
  lua_pushnumber(L, TB_KEY_CTRL_D           ); lua_setfield(L, -2, "KEY_CTRL_D");
  lua_pushnumber(L, TB_KEY_CTRL_E           ); lua_setfield(L, -2, "KEY_CTRL_E");
  lua_pushnumber(L, TB_KEY_CTRL_F           ); lua_setfield(L, -2, "KEY_CTRL_F");
  lua_pushnumber(L, TB_KEY_CTRL_G           ); lua_setfield(L, -2, "KEY_CTRL_G");
  lua_pushnumber(L, TB_KEY_BACKSPACE        ); lua_setfield(L, -2, "KEY_BACKSPACE");
  lua_pushnumber(L, TB_KEY_CTRL_H           ); lua_setfield(L, -2, "KEY_CTRL_H");
  lua_pushnumber(L, TB_KEY_TAB              ); lua_setfield(L, -2, "KEY_TAB");
  lua_pushnumber(L, TB_KEY_CTRL_I           ); lua_setfield(L, -2, "KEY_CTRL_I");
  lua_pushnumber(L, TB_KEY_CTRL_J           ); lua_setfield(L, -2, "KEY_CTRL_J");
  lua_pushnumber(L, TB_KEY_CTRL_K           ); lua_setfield(L, -2, "KEY_CTRL_K");
  lua_pushnumber(L, TB_KEY_CTRL_L           ); lua_setfield(L, -2, "KEY_CTRL_L");
  lua_pushnumber(L, TB_KEY_ENTER            ); lua_setfield(L, -2, "KEY_ENTER");
  lua_pushnumber(L, TB_KEY_CTRL_M           ); lua_setfield(L, -2, "KEY_CTRL_M");
  lua_pushnumber(L, TB_KEY_CTRL_N           ); lua_setfield(L, -2, "KEY_CTRL_N");
  lua_pushnumber(L, TB_KEY_CTRL_O           ); lua_setfield(L, -2, "KEY_CTRL_O");
  lua_pushnumber(L, TB_KEY_CTRL_P           ); lua_setfield(L, -2, "KEY_CTRL_P");
  lua_pushnumber(L, TB_KEY_CTRL_Q           ); lua_setfield(L, -2, "KEY_CTRL_Q");
  lua_pushnumber(L, TB_KEY_CTRL_R           ); lua_setfield(L, -2, "KEY_CTRL_R");
  lua_pushnumber(L, TB_KEY_CTRL_S           ); lua_setfield(L, -2, "KEY_CTRL_S");
  lua_pushnumber(L, TB_KEY_CTRL_T           ); lua_setfield(L, -2, "KEY_CTRL_T");
  lua_pushnumber(L, TB_KEY_CTRL_U           ); lua_setfield(L, -2, "KEY_CTRL_U");
  lua_pushnumber(L, TB_KEY_CTRL_V           ); lua_setfield(L, -2, "KEY_CTRL_V");
  lua_pushnumber(L, TB_KEY_CTRL_W           ); lua_setfield(L, -2, "KEY_CTRL_W");
  lua_pushnumber(L, TB_KEY_CTRL_X           ); lua_setfield(L, -2, "KEY_CTRL_X");
  lua_pushnumber(L, TB_KEY_CTRL_Y           ); lua_setfield(L, -2, "KEY_CTRL_Y");
  lua_pushnumber(L, TB_KEY_CTRL_Z           ); lua_setfield(L, -2, "KEY_CTRL_Z");
  lua_pushnumber(L, TB_KEY_ESC              ); lua_setfield(L, -2, "KEY_ESC");
  lua_pushnumber(L, TB_KEY_CTRL_LSQ_BRACKET ); lua_setfield(L, -2, "KEY_CTRL_LSQ_BRACKET");
  lua_pushnumber(L, TB_KEY_CTRL_3           ); lua_setfield(L, -2, "KEY_CTRL_3");
  lua_pushnumber(L, TB_KEY_CTRL_4           ); lua_setfield(L, -2, "KEY_CTRL_4");
  lua_pushnumber(L, TB_KEY_CTRL_BACKSLASH   ); lua_setfield(L, -2, "KEY_CTRL_BACKSLASH");
  lua_pushnumber(L, TB_KEY_CTRL_5           ); lua_setfield(L, -2, "KEY_CTRL_5");
  lua_pushnumber(L, TB_KEY_CTRL_RSQ_BRACKET ); lua_setfield(L, -2, "KEY_CTRL_RSQ_BRACKET");
  lua_pushnumber(L, TB_KEY_CTRL_6           ); lua_setfield(L, -2, "KEY_CTRL_6");
  lua_pushnumber(L, TB_KEY_CTRL_7           ); lua_setfield(L, -2, "KEY_CTRL_7");
  lua_pushnumber(L, TB_KEY_CTRL_SLASH       ); lua_setfield(L, -2, "KEY_CTRL_SLASH");
  lua_pushnumber(L, TB_KEY_CTRL_UNDERSCORE  ); lua_setfield(L, -2, "KEY_CTRL_UNDERSCORE");
  lua_pushnumber(L, TB_KEY_SPACE            ); lua_setfield(L, -2, "KEY_SPACE");
  lua_pushnumber(L, TB_KEY_BACKSPACE2       ); lua_setfield(L, -2, "KEY_BACKSPACE2");
  lua_pushnumber(L, TB_KEY_CTRL_8           ); lua_setfield(L, -2, "KEY_CTRL_8");

  lua_pushnumber(L, TB_META_SHIFT           ); lua_setfield(L, -2, "META_SHIFT");
  lua_pushnumber(L, TB_META_ALT             ); lua_setfield(L, -2, "META_ALT");
  lua_pushnumber(L, TB_META_ALTSHIFT        ); lua_setfield(L, -2, "META_ALTSHIFT");
  lua_pushnumber(L, TB_META_CTRL            ); lua_setfield(L, -2, "META_CTRL");
  lua_pushnumber(L, TB_META_CTRLSHIFT       ); lua_setfield(L, -2, "META_CTRLSHIFT");
  lua_pushnumber(L, TB_META_ALTCTRL         ); lua_setfield(L, -2, "META_ALTCTRL");
  lua_pushnumber(L, TB_META_ALTCTRLSHIFT    ); lua_setfield(L, -2, "META_ALTCTRLSHIFT");
  lua_pushnumber(L, TB_META_MOTION          ); lua_setfield(L, -2, "META_MOTION");

  return 1;
}
