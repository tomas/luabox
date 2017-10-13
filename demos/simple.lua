local tb = require "termbox"

if not tb.init() then
  print('tb_init failed.')
  return
end

local w  = tb.width()
local h  = tb.height()
local bg = tb.DEFAULT
local fg = tb.DEFAULT

tb.string((w/2)-6, h/2, bg, fg, "Hello click.")
tb.render()

ev = {}
clicks = 0
tb.enable_mouse()

repeat
  local t = tb.poll_event(ev)

  if t == tb.EVENT_KEY then
    if ev.ch == 'q' or ev.key == tb.KEY_ESC or ev.key == tb.KEY_CTRL_C then
      break
    end

  elseif t == tb.EVENT_RESIZE then
    tb.resize()
    w = ev.w
    h = ev.h

    tb.stringf((w/2)-10, h/2, bg, fg, "Window resized to: %dx%d", w, h)

  elseif t == tb.EVENT_MOUSE then

    if ev.key == tb.KEY_MOUSE_LEFT then
      clicks = clicks + 1
      tb.stringf((w/2)-10, h/2, bg, fg, "Click number %d! (%d, %d)", clicks, ev.x, ev.y)
    end
  end

  tb.render()
until not ev

tb.shutdown()