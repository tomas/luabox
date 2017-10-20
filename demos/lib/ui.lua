local tb = require('termbox')
local Object  = require('demos.lib.classic')
local Emitter = require('demos.lib.events')

local screen, window, last_click

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

function debug(obj)
  io.stderr:write(dump(obj) .. "\n")
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
  self.focus_fg = opts.focus_fg
  self.focus_bg = opts.focus_bg
  self.bg_char  = opts.bg_char or ' ' -- or 0x2573 -- 0x26EC -- 0x26F6 -- 0xFFEE -- 0x261B

  self.position = opts.position
  self.changed  = true
  self.hidden   = false
  self.parent   = nil
  self.children = {}
  self.emitter  = Emitter:new()

  -- cascade events down
  self:on('mouse_event', function(x, y, evt, ...)
    for _, child in ipairs(self.children) do
      if child:contains(x, y) then
        child:trigger('mouse_event', x, y, evt, ...)
        child:trigger(evt, x, y, ...)
      end
    end
  end)
end

function Box:__tostring()
  return string.format("<Box [w:%d,h:%d] [fg:%d,bg:%d]>", self.x, self.y, self.width or -1, self.height or -1, self.fg or -1, self.bg or -1)
end

function Box:unfocus()
  self.changed = true
end

function Box:focus()
  if self:is_focused() then return end
  if window.focused then
    window.focused:unfocus()
  end
  window.focused = self
  self.changed = true
end

function Box:is_focused()
  return window.focused == self
end

function Box:colors()
  local below_fg, below_bg

  if not self.parent then
    below_fg, below_bg = 0, 0
  else
    below_fg, below_bg = self.parent:colors()
  end

  local fg = self:is_focused() and self.focus_fg or (self.fg == nil and below_fg or self.fg)
  local bg = self:is_focused() and self.focus_bg or (self.bg == nil and below_bg or self.bg)

  return fg, bg
end

function Box:char(x, y, ch)
  local offset_x, offset_y = self:offset()
  local fg, bg = self:colors()
  tb.char(offset_x + x, offset_y + y, fg, bg, ch)
end

function Box:string(x, y, str)
  local offset_x, offset_y = self:offset()
  local fg, bg = self:colors()
  tb.string(offset_x + x, offset_y + y, fg, bg, str)
end

function Box:margin()
  local parent_w, parent_h = self.parent:size()

  -- position "top" is a bit unnecessary, but what the hell.
  local top    = self.position == "bottom" and (parent_h - self.height) or (self.top >= 1 and self.top or parent_h * self.top)
  local bottom = self.position == "top" and (parent_h - self.height) or (self.bottom >= 1 and self.bottom or parent_h * self.bottom)
  local left   = self.position == "right" and (parent_w - self.width) or (self.left >= 1 and self.left or parent_w * self.left)
  local right  = self.position == "right" and (parent_w - self.width) or (self.right >= 1 and self.right or parent_w * self.right)

  return top, right, bottom, left
end

function Box:offset()
  local x, y = self.parent:offset()
  local top, right, bottom, left = self:margin()
  return math.ceil(x + left), math.ceil(y + top)
end

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

function Box:trigger(evt, ...)
  self.emitter:emit(evt, ...)
end

function Box:add(child)
  if child.parent then
    print("Child already has a parent!")
    return
  end

  child.parent = self
  table.insert(self.children, child)
  self:trigger('child_added', child)
  self.changed = true
end

function Box:render_tree()
  for _, child in ipairs(self.children) do
    child:render()
  end
end

function Box:render_self()
  local offset_x, offset_y = self:offset()
  local width, height = self:size()

  local fg, bg = self:colors()

  for x = 0, math.ceil(width)-1, 1 do
    for y = 0, math.ceil(height)-1, 1 do
      -- self:char(x, y, self.bg_char)
      tb.char(x + offset_x, y + offset_y, fg, bg, self.bg_char)
    end
  end

  -- center = math.ceil(height/2)
  -- local top, right, bottom, left = self:margin()
  -- tb.string(offset_x+1, offset_y, fg, bg, string.format("%dx%d @ %dx%d [%d,%d,%d,%d]",
  -- width, height, offset_x, offset_y, top, right, bottom, left, center))
end

function Box:contains(x, y)
  local offset_x, offset_y = self:offset()
  local width, height = self:size()
  if (offset_x <= x and x < (offset_x + width)) and
     (offset_y <= y and y < (offset_y + height)) then
      return true
  else
    return false
  end
end

function Box:render()
  if not self.hidden then
    if self.changed then self:render_self() end
    self:render_tree()
    -- self.changed = false
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

----------------------------------------

TextBox = Box:extend()

function TextBox:new(text, opts)
  TextBox.super.new(self, opts or {})
  self:set_text(text)
end

function TextBox:set_text(text)
  self.text = text -- :gsub("\n", " ")
  self.chars = self.text:len()
end

function TextBox:render_self()
  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()

  local n, str, line, linebreak, limit = 0, self.text, nil, nil
  while string.len(str) > 0 do
    linebreak = string.find(str, '\n')
    if linebreak and linebreak <= width then
      line = str:sub(0, linebreak - 1)
      limit = linebreak + 1
    else
      line = str:sub(0, width)
      limit = width + 1
    end

    tb.string(x, y + n, fg, bg, line)
    n = n + 1
    str = str:sub(limit)
  end

  self.lines = n
end

EditableTextBox = TextBox:extend()

function EditableTextBox:new(text, opts)
  EditableTextBox.super.new(self, text, opts or {})

  self:on('left_click', function()
    self:focus()
  end)

  self:on('key', function(key, char, meta)
    if char == '' then
      self:handle_key(key, meta)
    else
      self:append_char(char)
    end
    self.changed = true
  end)
end

function EditableTextBox:handle_key(key, meta)
  if key == tb.KEY_ENTER then
    self:append_char('\n')
  elseif key == tb.KEY_BACKSPACE2 then
    self:delete_char(-1)
  elseif key == tb.KEY_DELETE then
    self:delete_char(0)
  elseif key == tb.KEY_HOME then
    self.cursor_pos = 0
  elseif key == tb.KEY_END then
    self.cursor_pos = self.text:len()
  elseif key == tb.KEY_ARROW_LEFT then
    self:move_cursor(-1)
  elseif key == tb.KEY_ARROW_RIGHT then
    self:move_cursor(1)
  elseif key == tb.KEY_ARROW_DOWN then
    local width, height = self:size()
    self:move_cursor(math.floor(width))
  elseif key == tb.KEY_ARROW_UP then
    local width, height = self:size()
    self:move_cursor(math.floor(width) * -1)
  end
end

function EditableTextBox:move_cursor(dir)
  local res = self.cursor_pos + dir

  if res < 0 or res > self.chars then
    return
  end

  self.cursor_pos = res
end

function EditableTextBox:set_text(text)
  EditableTextBox.super.set_text(self, text)
  self.cursor_pos = self.chars
end

function EditableTextBox:append_char(char)
  if self.cursor_pos == self.chars then
    self.text = self.text .. char
  else
    self.text = self.text:sub(0, self.cursor_pos) .. char .. self.text:sub(self.cursor_pos+1)
  end

  self.chars = self.chars + 1
  self.cursor_pos = self.cursor_pos + 1
end

function EditableTextBox:delete_char(at)
  if (self.cursor_pos == 0 and at < 0) or (self.cursor_pos == self.chars and at >= 0) then
    return
  end

  if self.cursor_pos == self.chars then
    self.text = self.text:sub(0, self.chars + at)
  else
    self.text = self.text:sub(0, self.cursor_pos + at) .. self.text:sub(self.cursor_pos+(at+2))
  end

  self.chars = self.chars - 1
  self.cursor_pos = self.cursor_pos + at
end

-- function num_matches(haystack, needle)
--   local count = 0
--   for i in string.gfind(haystack, needle) do
--      count = count + 1
--   end
--   return count
-- end

function contains_newline(str, stop)
  local subs = str:sub(0, stop)
  return subs:find('\n')
end

function EditableTextBox:get_cursor_offset(width)
  local pos = self.cursor_pos
  local str = self.text:sub(0, self.cursor_pos)

  if pos < width and not contains_newline(str, width-1) then
    return pos, 0
  end

  local x, y = 0, 0
  local n, chars, limit, nextbreak = 0, 0, 0
  while string.len(str) > 0 do

    nextbreak = string.find(str, '\n')
    if nextbreak and nextbreak <= width then
      line  = str:sub(0, nextbreak-1)
      limit = nextbreak + 1
      chars = chars + nextbreak
    else
      line = str:sub(0, width)
      limit = width + 1
      chars = chars + width
    end

    n = n + 1
    str = str:sub(limit)
    -- debug(string.format("chars: %d, pos: %d, width: %d, break: %d, line len: %d", chars, pos, width, nextbreak or '-1', line:len()))

    if chars == pos then
      y = n
      x = 0
      break
    elseif (chars < pos and chars + line:len() > pos) then
      if not contains_newline(str, pos - chars) then
        y = n
        x = pos - chars
        break
      end
    elseif chars > pos then
      y = n-1
      x = line:len()
      break
    end
  end

  return x, y
end

function EditableTextBox:render_cursor()
  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()

  local cursor_x, cursor_y = self:get_cursor_offset(math.floor(width))
  local char = self.text:sub(self.cursor_pos+1, self.cursor_pos+1)
  tb.string(x + cursor_x, y + cursor_y, fg, tb.RED, (char == '' or char == '\n') and ' ' or char)
end

function EditableTextBox:render_self()
  EditableTextBox.super.render_self(self)
  if (self:is_focused()) then
    self:render_cursor()
  end
end

----------------------------------------

Label = Box:extend()

function Label:new(text, opts)
  Label.super.new(self, opts or {})
  self.height = 1
  self.text = text
end

function Label:render_self()
  Label.super.render_self(self)

  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()

  tb.string(x, y, fg, bg, self.text:sub(0, width))
end

-----------------------------------------

List = Box:extend()

function List:new(items, opts)
  List.super.new(self, opts or {})
  self.pos = 1
  self.selected = -1
  self.items = items
  self.count = opts.count or table.getn(items)

  self:on('left_click', function()
    self:focus()
  end)

  self:on('key', function(key, ch)
    self.changed = true
    local w, h = self:size()

    if key == tb.KEY_HOME then
      self.pos = 0
    elseif key == tb.KEY_END then
      self.pos = self.count - h
    elseif key == tb.KEY_PAGE_DOWN then
      self:move(math.floor(h/2))
    elseif key == tb.KEY_PAGE_UP then
      self:move(math.floor(h/2) * -1)
    end
  end)

  self:on('scroll', function(x, y, dir)
    self.changed = true
    self:move(dir)
  end)
end

function List:move(dir)
  local res = dir + self.pos
  local width, height = self:size()

  -- ensure we stay within bounds
  if res < 1 -- and that the don't show an empty box
      or dir > 0 and res > (self.count - height + dir)
        then return
  end

  self.pos = res
end

function List:get_item(number)
  return self.items[number]
end

function List:render_self()
  local x, y = self:offset()
  local width, height = self:size()
  local fg, bg = self:colors()

  local index, item
  for line = 0, height, 1 do
    index = line + self.pos
    item = self:get_item(index)
    if not item then break end
    tb.string(x, y + line, fg, index == self.selected and tb.BLACK or bg, item:sub(0, width))
  end
end

-----------------------------------------

OptionList = List:extend()

function OptionList:new(items, opts)
  OptionList.super.new(self, items, opts)

  self:on('left_click', function(mouse_x, mouse_y)
    local x, y = self:offset()
    self:select(self.pos + (mouse_y - y))
    self.changed = true
  end)

  self:on('double_click', function(mouse_x, mouse_y)
    self:submit()
  end)
end

function OptionList:select(number)
  if (number < 1 or number > self.count) then return end
  self.selected = number
  self:trigger('selected', self.selected, self.items[self.selected])
end

function OptionList:submit()
  self:trigger('submit', self.selected, self.items[self.selected])
end

-----------------------------------------

function load(opts)
  if not tb.init() then return end
  tb.enable_mouse()

  screen = Container({
    width = tb.width(),
    height = tb.height()
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
  window:trigger('key:' .. key, key, char, meta)

  if window.focused then
    window.focused:trigger('key', key, char, meta)
    window.focused:trigger('key:' .. key, key, char, meta)
  end
end

local mouse_events = {
  [tb.KEY_MOUSE_LEFT]       = 'left_click',
  [tb.KEY_MOUSE_MIDDLE]     = 'middle_click',
  [tb.KEY_MOUSE_RIGHT]      = 'right_click',
  -- [tb.KEY_MOUSE_RELEASE]    = 'mouseup',
  [tb.KEY_MOUSE_WHEEL_UP]   = 'scroll_up',
  [tb.KEY_MOUSE_WHEEL_DOWN] = 'scroll_down'
}

function on_click(key, x, y, count)
  local event = mouse_events[key]
  if not event then return false end

  window:trigger('mouse_event', x, y, event:sub(0))

  if event:match('_click') then
    -- trigger a 'click' event for all mouse clicks
    window:trigger('mouse_event', x, y, 'click')

    if count == 2 then
      window:trigger('mouse_event', x, y, 'double_click')
    elseif count == 3 then
      window:trigger('mouse_event', x, y, 'triple_click')
    end

  elseif event:match('scroll_') then
    -- trigger a 'scroll' event for up/down
    local dir = key == tb.KEY_MOUSE_WHEEL_UP and -2 or 2
    window:trigger('mouse_event', x, y, 'scroll', dir)
  end

end

function on_resize(w, h)
  tb.resize()
  screen.width  = w
  screen.height = h
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
      on_click(ev.key, ev.x, ev.y, ev.clicks)

    elseif res == tb.EVENT_RESIZE then
      on_resize(ev.w, ev.h)
    end
  until res == -1
end

local ui  = {}
ui.load   = load
ui.unload = unload
ui.start  = start
ui.render = render
ui.bold   = tb.bold

ui.Box        = Box
ui.Label      = Label
ui.TextBox    = TextBox
ui.EditableTextBox = EditableTextBox
ui.List       = List
ui.OptionList = OptionList

return ui