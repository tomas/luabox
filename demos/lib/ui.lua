local tb = require('termbox')
local Object  = require('demos.lib.classic')
local Emitter = require('demos.lib.events')

function dump(o)
 if type(o) == 'table' then
  local s = '{ '
  for k,v in pairs(o) do
    if type(k) ~= 'number' then k = '"'..k..'"' end
    s = s .. '['..k..'] = ' .. dump(v) .. ', '
  end
  return s .. '} '
 else
   return tostring(o)
 end
end

Rect = Object:extend()

function Rect:new(opts)
  self.width  = opts.width
  self.height = opts.height
end

Container = Rect:extend()

function Container:new(opts)
  Container.super.new(self, opts)
  self.top    = opts.top or 0
  self.bottom = opts.bottom or 0
  self.left   = opts.left or 0
  self.right  = opts.right or 0
end

function Container:offset()
  return self.top, self.left
end

function Container:size()
  return self.width, self.height
end

function Container:colors()
  return 0, 0
end

Box = Container:extend()

function Box:new(opts)
  opts = opts or {}
  Box.super.new(self, opts)
  self.fg       = opts.fg
  self.bg       = opts.bg
  self.bg_char  = opts.bg_char or ' '

  self.focused  = false
  self.hidden   = false
  self.parent   = nil
  self.children = {}
  self.emitter  = Emitter:new()

  self:on('click', function(x, y)
    self.focused = true
    for _, child in ipairs(self.children) do
      if child:contains(x, y) then
        child:trigger('click', x, y)
      else
        child.focused = false
      end
    end
  end)
end

function Box:__tostring()
  return string.format("<Box [w:%d,h:%d] [fg:%d,bg:%d]>", self.x, self.y, self.width or -1, self.height or -1, self.fg or -1, self.bg or -1)
end

function Box:colors()
  local below_fg, below_bg

  if not self.parent then
    below_fg, below_bg = 0, 0
  else
    below_fg, below_bg = self.parent:colors()
  end

  local fg = self.fg == nil and below_fg or self.fg
  local bg = self.bg == nil and below_bg or self.bg

  return fg, bg
end

-- function Box:coords()
--   if not self.parent then -- root window
--     return self.x, self.y
--   else
--     local x, y = self.x + self.padding, self.y + self.padding
--     local parent_x, parent_y = self.parent:coords()
--     return parent_x + x, parent_y + y
--   end
-- end

function Box:offset()
  local x, y = self.parent:offset()
  local top, right, bottom, left = self:margin()
  return (x + left), (y + top)
end

function Box:margin()
  local parent_w, parent_h = self.parent:size()
  local top    = self.top >= 1 and self.top or parent_h * self.top
  local bottom = self.bottom >= 1 and self.bottom or parent_h * self.bottom
  local left   = self.left >= 1 and self.left or parent_w * self.left
  local right  = self.right >= 1 and self.right or parent_w * self.right

  return top, right, bottom, left
end

-- function Box:char(x, y, ch)
--   local offset_x, offset_y = self:offset()
--   tb.char(offset_x + x, offset_y + y, fg, bg, ch)
-- end

function Box:size()
  local w, h
  local parent_w, parent_h = self.parent:size()
  local top, right, bottom, left = self:margin()

  if self.width then -- width of parent
    w = self.width >= 1 and self.width or parent_w * self.width
  else -- width not set. parent width minus
    w = parent_w - (left + right)
  end

  if self.height then -- width of parent
    h = self.height >= 1 and self.height or parent_h * self.height
  else -- width not set. parent width minus
    h = parent_h - (top + bottom)
  end

  return w, h
end

function Box:on(evt, fn)
  self.emitter:on(evt, fn)
end

function Box:trigger(evt, arg1, arg2)
  self.emitter:emit(evt, arg1, arg2)
end

function Box:add(child)
  if child.parent then
    print("Child already has a parent!")
    return
  end

  child.parent = self
  table.insert(self.children, child)
  self:trigger('child_added', child)
end

function Box:render_tree()
  for _, child in ipairs(self.children) do
    child:render()
  end
end

function Box:render_self()
  local offset_x, offset_y = self:offset()
  local width, height = self:size()
  local top, right, bottom, left = self:margin()
  local fg, bg = self:colors()
  local lastx, lasty

  local bg = self.focused and tb.RED or bg

  for x = 0, width, 1 do
    for y = 0, height, 1 do
      tb.char(x + offset_x, y + offset_y, fg, bg, self.bg_char)
      lasty = y
    end
    lastx = x
  end

  center = math.ceil(height/2)
  tb.string(offset_x+1, offset_y, fg, bg, string.format("%dx%d @ %dx%d [%d,%d,%d,%d] - %d -- [%d/%d]",
    width, height, offset_x, offset_y, top, right, bottom, left, center, lastx, lasty))
end

function Box:contains(x, y)
  local offset_x, offset_y = self:offset()
  local width, height = self:size()
  if (offset_x <= x and x <= (offset_x + width)) and
    (offset_y <= y and y <= (offset_y + height)) then
      return true
  else
    return false
  end
end

function Box:render()
  if not self.hidden then
    self:render_self()
    self:render_tree()
  end
end

function Box:remove_tree()
  for _, child in ipairs(self.children) do
    child:remove()
  end
end

function Box:remove()
  self:remove_tree()
  self.emitter:removeAllListeners()
  self.hidden = true
end

Label = Box:extend()

function Label:new(text, opts)
  Label.super.new(self, opts or {})
  self.height = 1
  self.text = text
end

function Label:render_self()
  local x, y = self:coords()
  -- local w, h = self:rect()
  local fg, bg = self:colors()
  tb.string(x, y, fg, bg, self.text)
end

-----------------------------------------

local screen, window, focused

function load(opts)
  if not tb.init() then return end
  tb.enable_mouse()

  screen = Container({
    width = tb.width(),
    height = tb.height()-1
  })

  window = Box({
    fg = tb.DEFAULT,
    bg = tb.DEFAULT
  })

  window.parent = screen
  return window
end

function unload()
  -- window:remove()
  tb.shutdown()
end

function on_key(key, char, meta)
  window:trigger('key', key, char, meta)
end

function on_click(button, x, y)
  window:trigger('click', x, y)
end

function on_resize(w, h)
  tb.resize()
  screen.width  = w
  screen.height = h-1
  window:trigger('resized', w, h)
end

function render()
  window:render()
  tb.render()
end

function start()
  local res, ev = nil, {}
  repeat
    render()
    res = tb.poll_event(ev)

    if res == tb.EVENT_KEY then
      if ev.key == tb.KEY_ESC or ev.key == tb.KEY_CTRL_C then break end
      on_key(ev.key, ev.ch, ev.meta)

    elseif res == tb.EVENT_MOUSE then
      on_click(ev.key, ev.x, ev.y)

    elseif res == tb.EVENT_RESIZE then
      on_resize(ev.w, ev.h)
    end
  until res == -1
end

local ui = {}
ui.load = load
ui.unload = unload
ui.start  = start
ui.render = render

ui.Box = Box
ui.Label = Label

return ui