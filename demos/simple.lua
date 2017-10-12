tb = require "termbox"

if not tb.init() then
  print('tb_init failed.')
  return
end

local w  = tb.width()
local h  = tb.height()
local bg = tb.DEFAULT
local fg = tb.DEFAULT

tb.print((w/2)-6, h/2, bg, fg, "Hello click.")
tb.present()

t = {}
clicks = 0
tb.enable_mouse()

repeat
  ev = tb.poll_event(t)

  if ev == tb.EVENT_KEY then
    if t.ch == 'q' or t.key == tb.CTRL_C then
      break
    end

  elseif ev == tb.EVENT_RESIZE then
    tb.clear()
    w = tb.width()
    h = tb.height()

    tb.printf((w/2)-10, h/2, bg, fg, "Window resized to: %dx%d", w, h)

  elseif ev == tb.EVENT_MOUSE then

    if t.key == tb.KEY_MOUSE_LEFT then
      clicks = clicks + 1
      tb.printf((w/2)-10, h/2, bg, fg, "Click number %d! (%d, %d)", clicks, t.x, t.y)
    end
  end

  tb.present()
until not ev

tb.shutdown()