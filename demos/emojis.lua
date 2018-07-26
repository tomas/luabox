local tb = require('luabox')

if not tb.init(tb.TB_INIT_KEYPAD) then
  print('tb_init failed.')
  return
end

local w  = tb.width()
local h  = tb.height()
local bg = tb.DEFAULT
local fg = tb.DEFAULT

tb.string(0, 0, tb.WHITE, tb.BLACK, "☻Hello click.", 10)
tb.string(0, 1, tb.BLACK, tb.WHITE, "😀Hello click.", 10)
tb.string(0, 2, tb.WHITE, tb.BLACK, " Hello click.", 10)
tb.render()

local ev = {}
-- clicks = 0
-- tb.enable_mouse()

repeat
  local t = tb.poll_event(ev)

  if t == tb.EVENT_KEY then
    if ev.ch == 'q' or ev.key == tb.KEY_ESC or ev.key == tb.KEY_CTRL_C then
      break
    end
  end

  tb.render()
until not ev

tb.shutdown()