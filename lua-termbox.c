#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h> // malloc, free
#include <string.h> // strlen, strncpy
#include <termbox.h>
#include "util.h"

#if defined(LUA_VERSION_NUM) && LUA_VERSION_NUM == 501
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
  #define luaL_checkunsigned(L, narg) (luaL_checknumber(L, narg))
  #define luaL_len(L, idx)            (lua_objlen(L, idx))
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

static int l_tb_char(lua_State* L) {
  int x       = luaL_checkinteger(L, 1);
  int y       = luaL_checkinteger(L, 2);
  uint16_t fg = luaL_checkunsigned(L, 3);
  uint16_t bg = luaL_checkunsigned(L, 4);
  const char * str = luaL_checkstring(L, 5);

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

  lua_pop(L, 5);
  tb_char(x, y, fg, bg, ch);
  return 0;
}

static int l_tb_string(lua_State *L) {
  int x = luaL_checkinteger(L, 1);
  int y = luaL_checkinteger(L, 2);
  int fg = luaL_checkinteger(L, 3);
  int bg = luaL_checkinteger(L, 4);
  const char * str = luaL_checkstring(L, 5);

  int len = tb_string(x, y, fg, bg, (char *)str);
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
    char string[2] = {event.ch,'\0'};
    string[0] = event.ch;

    lua_pushstring(L, string);
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
  uint32_t *out = (uint32_t*)(uintptr_t)luaL_checkunsigned(L, 1);
  const char *c = luaL_checkstring(L, 2);

  lua_pop(L, 2);
  lua_pushinteger(L, tb_utf8_char_to_unicode(out, c));
  return 1;
}

static int l_tb_utf8_unicode_to_char(lua_State *L) {
  uint32_t *out = (uint32_t*)(uintptr_t)luaL_checkunsigned(L, 1);
  const char *c = luaL_checkstring(L, 2);

  lua_pop(L, 2);
  lua_pushinteger(L, tb_utf8_char_to_unicode(out, c));
  return 1;
}

///////////////////
// helpers

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

static const struct luaL_Reg l_termbox[] = {
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
  {NULL,NULL}
};

/* remove TB_ prefix and register constant */
#define REGISTER_CONSTANT(constant) {\
  char* full_name = #constant; \
  unsigned len = strlen(full_name)+1; \
  char* name = (char*)malloc(len-3); \
  strncpy(name, full_name+3, len-3); \
  lua_pushnumber(L, constant); \
  lua_setfield(L, -2, name); \
  free(name); \
}

int luaopen_termbox (lua_State *L) {
  luaL_newlib(L, l_termbox);

  REGISTER_CONSTANT(TB_KEY_F1);
  REGISTER_CONSTANT(TB_KEY_F2);
  REGISTER_CONSTANT(TB_KEY_F3);
  REGISTER_CONSTANT(TB_KEY_F4);
  REGISTER_CONSTANT(TB_KEY_F5);
  REGISTER_CONSTANT(TB_KEY_F6);
  REGISTER_CONSTANT(TB_KEY_F7);
  REGISTER_CONSTANT(TB_KEY_F8);
  REGISTER_CONSTANT(TB_KEY_F9);
  REGISTER_CONSTANT(TB_KEY_F10);
  REGISTER_CONSTANT(TB_KEY_F11);
  REGISTER_CONSTANT(TB_KEY_F12);
  REGISTER_CONSTANT(TB_KEY_INSERT);
  REGISTER_CONSTANT(TB_KEY_DELETE);
  REGISTER_CONSTANT(TB_KEY_HOME);
  REGISTER_CONSTANT(TB_KEY_END);
  REGISTER_CONSTANT(TB_KEY_PGUP);
  REGISTER_CONSTANT(TB_KEY_PGDN);
  REGISTER_CONSTANT(TB_KEY_PAGE_UP);
  REGISTER_CONSTANT(TB_KEY_PAGE_DOWN);

  REGISTER_CONSTANT(TB_KEY_ARROW_UP);
  REGISTER_CONSTANT(TB_KEY_ARROW_DOWN);
  REGISTER_CONSTANT(TB_KEY_ARROW_LEFT);
  REGISTER_CONSTANT(TB_KEY_ARROW_RIGHT);

  REGISTER_CONSTANT(TB_KEY_MOUSE_LEFT);
  REGISTER_CONSTANT(TB_KEY_MOUSE_RIGHT);
  REGISTER_CONSTANT(TB_KEY_MOUSE_MIDDLE);
  REGISTER_CONSTANT(TB_KEY_MOUSE_RELEASE);
  REGISTER_CONSTANT(TB_KEY_MOUSE_WHEEL_UP);
  REGISTER_CONSTANT(TB_KEY_MOUSE_WHEEL_DOWN);

  REGISTER_CONSTANT(TB_KEY_CTRL_TILDE);
  REGISTER_CONSTANT(TB_KEY_CTRL_2);
  REGISTER_CONSTANT(TB_KEY_CTRL_A);
  REGISTER_CONSTANT(TB_KEY_CTRL_B);
  REGISTER_CONSTANT(TB_KEY_CTRL_C);
  REGISTER_CONSTANT(TB_KEY_CTRL_D);
  REGISTER_CONSTANT(TB_KEY_CTRL_E);
  REGISTER_CONSTANT(TB_KEY_CTRL_F);
  REGISTER_CONSTANT(TB_KEY_CTRL_G);
  REGISTER_CONSTANT(TB_KEY_BACKSPACE);
  REGISTER_CONSTANT(TB_KEY_CTRL_H);
  REGISTER_CONSTANT(TB_KEY_TAB);
  REGISTER_CONSTANT(TB_KEY_CTRL_I);
  REGISTER_CONSTANT(TB_KEY_CTRL_J);
  REGISTER_CONSTANT(TB_KEY_CTRL_K);
  REGISTER_CONSTANT(TB_KEY_CTRL_L);
  REGISTER_CONSTANT(TB_KEY_ENTER);
  REGISTER_CONSTANT(TB_KEY_CTRL_M);
  REGISTER_CONSTANT(TB_KEY_CTRL_N);
  REGISTER_CONSTANT(TB_KEY_CTRL_O);
  REGISTER_CONSTANT(TB_KEY_CTRL_P);
  REGISTER_CONSTANT(TB_KEY_CTRL_Q);
  REGISTER_CONSTANT(TB_KEY_CTRL_R);
  REGISTER_CONSTANT(TB_KEY_CTRL_S);
  REGISTER_CONSTANT(TB_KEY_CTRL_T);
  REGISTER_CONSTANT(TB_KEY_CTRL_U);
  REGISTER_CONSTANT(TB_KEY_CTRL_V);
  REGISTER_CONSTANT(TB_KEY_CTRL_W);
  REGISTER_CONSTANT(TB_KEY_CTRL_X);
  REGISTER_CONSTANT(TB_KEY_CTRL_Y);
  REGISTER_CONSTANT(TB_KEY_CTRL_Z);
  REGISTER_CONSTANT(TB_KEY_ESC);
  REGISTER_CONSTANT(TB_KEY_CTRL_LSQ_BRACKET);
  REGISTER_CONSTANT(TB_KEY_CTRL_3);
  REGISTER_CONSTANT(TB_KEY_CTRL_4);
  REGISTER_CONSTANT(TB_KEY_CTRL_BACKSLASH);
  REGISTER_CONSTANT(TB_KEY_CTRL_5);
  REGISTER_CONSTANT(TB_KEY_CTRL_RSQ_BRACKET);
  REGISTER_CONSTANT(TB_KEY_CTRL_6);
  REGISTER_CONSTANT(TB_KEY_CTRL_7);
  REGISTER_CONSTANT(TB_KEY_CTRL_SLASH);
  REGISTER_CONSTANT(TB_KEY_CTRL_UNDERSCORE);
  REGISTER_CONSTANT(TB_KEY_SPACE);
  REGISTER_CONSTANT(TB_KEY_BACKSPACE2);
  REGISTER_CONSTANT(TB_KEY_CTRL_8);

  REGISTER_CONSTANT(TB_META_SHIFT);
  REGISTER_CONSTANT(TB_META_ALT);
  REGISTER_CONSTANT(TB_META_ALTSHIFT);
  REGISTER_CONSTANT(TB_META_CTRL);
  REGISTER_CONSTANT(TB_META_CTRLSHIFT);
  REGISTER_CONSTANT(TB_META_ALTCTRL);
  REGISTER_CONSTANT(TB_META_ALTCTRLSHIFT);

  REGISTER_CONSTANT(TB_DEFAULT);
  REGISTER_CONSTANT(TB_BLACK);
  REGISTER_CONSTANT(TB_RED);
  REGISTER_CONSTANT(TB_GREEN);
  REGISTER_CONSTANT(TB_YELLOW);
  REGISTER_CONSTANT(TB_BLUE);
  REGISTER_CONSTANT(TB_MAGENTA);
  REGISTER_CONSTANT(TB_CYAN);
  REGISTER_CONSTANT(TB_WHITE);

  REGISTER_CONSTANT(TB_LIGHT_GRAY);
  REGISTER_CONSTANT(TB_MEDIUM_GRAY);
  REGISTER_CONSTANT(TB_LIGHT_RED);
  REGISTER_CONSTANT(TB_LIGHT_GREEN);
  REGISTER_CONSTANT(TB_LIGHT_YELLOW);
  REGISTER_CONSTANT(TB_LIGHT_BLUE);
  REGISTER_CONSTANT(TB_LIGHT_MAGENTA);
  REGISTER_CONSTANT(TB_LIGHT_CYAN);
  REGISTER_CONSTANT(TB_WHITE);

  REGISTER_CONSTANT(TB_DARKEST_GREY);
  REGISTER_CONSTANT(TB_DARKER_GREY);
  REGISTER_CONSTANT(TB_DARK_GREY);
  REGISTER_CONSTANT(TB_MEDIUM_GREY);
  REGISTER_CONSTANT(TB_LIGHT_GREY);
  REGISTER_CONSTANT(TB_LIGHTER_GREY);
  REGISTER_CONSTANT(TB_LIGHTEST_GREY);

  REGISTER_CONSTANT(TB_BOLD);
  REGISTER_CONSTANT(TB_UNDERLINE);
  REGISTER_CONSTANT(TB_REVERSE);

  REGISTER_CONSTANT(TB_EVENT_KEY);
  REGISTER_CONSTANT(TB_EVENT_RESIZE);
  REGISTER_CONSTANT(TB_EVENT_MOUSE);

  REGISTER_CONSTANT(TB_INIT_ALL);
  REGISTER_CONSTANT(TB_INIT_ALTSCREEN);
  REGISTER_CONSTANT(TB_INIT_KEYPAD);
  REGISTER_CONSTANT(TB_INIT_NO_CURSOR);
  REGISTER_CONSTANT(TB_INIT_DETECT_MODE);

  REGISTER_CONSTANT(TB_EUNSUPPORTED_TERMINAL);
  REGISTER_CONSTANT(TB_EFAILED_TO_OPEN_TTY);
  REGISTER_CONSTANT(TB_EPIPE_TRAP_ERROR);

  REGISTER_CONSTANT(TB_OUTPUT_NORMAL);
  REGISTER_CONSTANT(TB_OUTPUT_256);
#ifdef WITH_TRUECOLOR
  REGISTER_CONSTANT(TB_OUTPUT_TRUECOLOR);
#endif

  REGISTER_CONSTANT(TB_EOF);
  return 1;
}