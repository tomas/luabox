local tb = require('lua-termbox')
local Object  = require('demos.lib.classic')
local Emitter = require('demos.lib.events')

local screen, window, last_click, stopped
local box_count = 0

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

function errwrite(str)
  io.stderr:write(str .. "\n")
end

function debug(obj)
  errwrite(dump(obj))
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

-------------------------------------------------------------

local Rect = Object:extend()

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

local Box = Container:extend()

Box.next_id = function()
  local curr = box_count
  box_count = box_count + 1
  return "box " .. curr
end

function Box:new(opts)
  opts = opts or {}
  Box.super.new(self, opts)

  self.id       = opts.id or Box.next_id()
  self.fg       = opts.fg
  self.bg       = opts.bg
  self.focus_fg = opts.focus_fg
  self.focus_bg = opts.focus_bg
  self.bg_char  = opts.bg_char or ' ' -- or 0x2573 -- 0x26EC -- 0x26F6 -- 0xFFEE -- 0x261B

  self.position = opts.position
  self.changed  = true
  self.hidden   = opts.hidden or false
  self.parent   = nil
  self.children = {}
  self.emitter  = Emitter:new()

  self:on('resized', function(new_w, new_h)
    self.changed = true
    for _, child in ipairs(self.children) do
      child:trigger('resized', new_w, new_h)
    end
  end)

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
  local w, h = self:size()
  return string.format("<Box [w:%d,h:%d] [x:%d/y:%d] [fg:%d,bg:%d]>", w, h, self.x, self.y, self.width or -1, self.height or -1, self.fg or -1, self.bg or -1)
end

function Box:toggle(bool)
  self.changed = true

  if bool == true or bool == false then
    self.hidden = not bool
    return self.hidden
  elseif self.hidden then
    self.hidden = false
    return true -- now shown
  else
    self.hidden = true
    return false  -- not shown now
  end
end

function Box:unfocus()
  self:trigger('unfocused')
  self.changed = true
end

function Box:focus()
  if self:is_focused() then return end

  -- unfocus whatever box is marked as focused
  if window.focused then
    window.focused:unfocus()
  end

  self:trigger('focused')
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

  -- raw width to calculate in case the width is %
  local w, h = self.width, self.height
  if w and w < 1 then w = w * parent_w end
  if h and h < 1 then h = h * parent_h end

  -- position "top" is a bit unnecessary, but what the hell.
  local top    = self.position == "bottom" and (parent_h - h) or (self.top >= 1 and self.top or parent_h * self.top)
  local bottom = self.position == "top" and (parent_h - h) or (self.bottom >= 1 and self.bottom or parent_h * self.bottom)
  local left   = self.position == "right" and (parent_w - w) or (self.left >= 1 and self.left or parent_w * self.left)
  local right  = self.position == "left" and (parent_w - w) or (self.right >= 1 and self.right or parent_w * self.right)

  return top, right, bottom, left
end

function Box:offset()
  local x, y = self.parent:offset()
  local top, right, bottom, left = self:margin()
  return math.ceil(x + left), math.ceil(y + top)
end

function Box:size()
  if self.hidden then
    return 0, 0
  end

  local w, h
  local parent_w, parent_h = self.parent:size()
  local top, right, bottom, left = self:margin()

  if self.width then -- width of parent
    w = self.width >= 1 and self.width or parent_w * self.width
  else -- width not set. parent width minus
    w = parent_w - (left + right)
    -- debug({ "width not set", self.id, parent_w, left, right, "result => ", w })
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

function Box:clear()
  local offset_x, offset_y = self:offset()
  local width, height = self:size()
  local fg, bg = self:colors()

  -- debug({ "clearing " .. self.id, offset_x, width })
  for x = 0, math.ceil(width)-1, 1 do
    for y = 0, math.ceil(height)-1, 1 do
      -- self:char(x, y, self.bg_char)
      tb.char(x + offset_x, y + offset_y, fg, bg, self.bg_char)
    end
  end
end

function Box:render_self()
  self:clear()
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
    self.changed = false
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

local TextBox = Box:extend()

function TextBox:new(text, opts)
  TextBox.super.new(self, opts or {})
  self:set_text(text)

  self:on('left_click', function(mouse_x, mouse_y)
    self:focus()
  end)
end

function TextBox:set_text(text)
  self.changed = true
  self.text = text -- :gsub("\n", " ")
  self.chars = self.text:len()
end

function TextBox:render_self()
  -- TextBox.super.clear(self)
  self:clear()

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
      -- check if remaining string is shorter than width
      local diff = width - str:len()

      if diff > 0 then -- yep, this is the last line
        line = str -- .. string.rep(' ', diff) -- fill with empty spaces
      else
        line = str:sub(0, width)
      end

      limit = width + 1
    end

    tb.string(x, y + n, fg, bg, line)
    n = n + 1
    str = str:sub(limit)
  end

  self.lines = n
end

local EditableTextBox = TextBox:extend()

function EditableTextBox:new(text, opts)
  EditableTextBox.super.new(self, text, opts or {})

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

function EditableTextBox:get_cursor_offset(width)
  local pos = self.cursor_pos
  local str = self.text:sub(0, self.cursor_pos)

  if pos < width and not contains_newline(str, width-1) then
    return pos, 0
  end

  local x, y, line = 0, 0, nil
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

local Label = Box:extend()

function Label:new(text, opts)
  Label.super.new(self, opts or {})
  self.height = 1
  self.text = text
end

function Label:set_text(text)
  self.text = text
  self.changed = true
end

function Label:render_self()
  Label.super.render_self(self)

  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()

  tb.string(x, y, fg, bg, self.text:sub(0, width))
end

-----------------------------------------

local List = Box:extend()

function List:new(items, opts)
  List.super.new(self, opts or {})
  self.pos = 1
  self.selected = 0
  self.items = items or {}

  self.selection_fg = opts.selection_fg
  self.selection_bg = opts.selection_bg or tb.BLACK

  self:on('left_click', function(mouse_x, mouse_y)
    self:focus()
  end)

  self:on('key', function(key, ch)
    self.changed = true
    local w, h = self:size()

    if key == tb.KEY_ARROW_DOWN then
      self:move(1)
    elseif key == tb.KEY_ARROW_UP then
      self:move(-1)
    elseif key == tb.KEY_HOME then
      self:move_to(1)
    elseif key == tb.KEY_END then
      if self:num_items() then -- known item count
        self:move_to(self:num_items() - h)
      else -- unknown, just forward one page
        self:move(math.floor(h/2))
      end
    elseif key == tb.KEY_PAGE_DOWN then
      self:move(math.floor(h/2))
    elseif key == tb.KEY_PAGE_UP then
      self:move(math.floor(h/2) * -1)
    end
  end)

  self:on('scroll', function(x, y, dir)
    self:move(dir)
  end)
end

function List:move_to(pos)
  self.changed = true
  self.pos = pos
end

function List:move(dir)
  local result = dir + self.pos
  local width, height = self:size()
  local nitems = self:num_items()

  -- ensure we stay within bounds
  if result < 1 -- and that the don't show an empty box
      or dir > 0 and (nitems and result > (nitems - height + dir))
        then return
  end

  self:move_to(result)
end

function List:num_items()
  if not self.items then
    return nil
  end

  table.getn(self.items)
end

function List:clear_items()
  self:set_items({})
end

function List:set_items(arr)
  self.items = arr
  self.selected = 0
  self.changed = true
end

function List:set_item(number, item)
  self.items[number] = item
  self.selected = 0
  self.changed = true
end

function List:get_item(number)
  return self.items[number]
end

function List:format_item(item)
  return tostring(item)
end

--[[
function List:selection_color(index, our_color, parent_color)
  if index == self.selected then
    return our_color or parent_color
  else
    return parent_color
  end
end
]]--

function List:render_self()
  self:clear()

  local x, y = self:offset()
  local width, height = self:size()
  local fg, bg = self:colors()
  local rounded_width = width % 1 == 0 and width or math.floor(width)+1
  local index, item, formatted, diff

  -- if self.title then
  --   self.title:set_text("Width: " .. width .. ", rounded: " .. rounded_width)
  -- end

  for line = 0, height-1, 1 do
    index = line + self.pos
    item = self:get_item(index)
    if not item then break end

    formatted = self:format_item(item)
    diff = width - formatted:len()
    if diff >= 0 then -- line is shorter than width
      formatted = formatted -- .. string.rep(' ', diff)
    else -- line is longer, so cut!
      formatted = formatted:sub(0, rounded_width-1) .. '$'
    end

    -- debug({ " --> line " .. index , formatted })
    tb.string(x, y + line,
      index == self.selected and self.selection_fg or fg,
      index == self.selected and self.selection_bg or bg,
      formatted)
  end
end

-----------------------------------------

local OptionList = List:extend()

function OptionList:new(items, opts)
  OptionList.super.new(self, items, opts)

  self:on('key', function(key, ch)
    if ch == ' ' then -- space key
      self:submit()
    end
  end)

  self:on('left_click', function(mouse_x, mouse_y)
    local x, y = self:offset()
    self:select(self.pos + (mouse_y - y))
  end)

  self:on('double_click', function(mouse_x, mouse_y)
    self:submit()
  end)
end

function OptionList:move(pos)
  -- if within screen, just move selection. otherwise, do move
  if pos == 1 or pos == -1 then
    self:select(self.selected + pos)
  else
    OptionList.super.move(self, pos)
  end
end

function OptionList:select(number)
  -- check if within bounds and actually changed
  if (number < 1 or number == self.selected or not self:get_item(number)) then return end

  self.changed = true
  self.selected = number
  self:trigger('selected', number, self:get_item(number))
end

function OptionList:submit()
  local item = self:get_item(self.selected)
  if item then
    self:trigger('submit', self.selected, item)
  end
end

-----------------------------------------

local Menu = OptionList:extend()

function Menu:new(items, opts)
  Menu.super.new(self, items, opts)
  self.hidden = true

  self.max_width  = opts.max_width -- otherwise, longest element + 1
  self.max_height = opts.max_height or 10

  -- selected is triggered on left click
  self:on('selected', function(index, item)
    self:submit()
  end)

  -- hide menu on submit
  -- update: no need to. window.hide_above will do this for us
  -- self:on('submit', function(index, item)
  --   self:toggle(false)
  -- end)
end

function Menu:open()
  self:toggle(true)
end

function Menu:close()
  self:toggle(false)
end

function Menu:set_offset(x, y)
  self.offset_x = x
  self.offset_y = y
end

function Menu:offset()
  if self.offset_x and self.offset_y then
    return self.offset_x, self.offset_y
  else
    return Menu.super.offset(self)
  end
end

function Menu:get_longest_item()
  local res, formatted
  for _, item in ipairs(self.items) do
    formatted = self:format_item(item)
    if not res or formatted:len() > res:len() then
      res = formatted
    end
  end

  return res
end

function Menu:size()
  local w, h = self.width, table.getn(self.items)

  if not w then
    w = string.len(self:get_longest_item())
  end

  return w, h
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
    id = "window",
    fg = tb.DEFAULT,
    bg = tb.DEFAULT
  })

  window.show_above = function(self, item)
    if self.above_item then
      self:hide_above()
    end
    -- self:add(item)
    self.above_item = item
    item:open()
  end

  window.hide_above = function(self)
    if self.above_item then
      self.above_item:close()
      -- self:remove(above_item)
      self.above_item = nil
      self:trigger('resized') -- force redraw of child elements
    end
  end

  window.parent = screen
  return window
end

function unload()
  if window then
    window:remove()
    window = nil
    tb.shutdown()
  end
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

  if window.above_item then
    if window.above_item:contains(x, y) then
      window.above_item:trigger(event, x, y)
    end
    window:hide_above()
    return -- we don't want to propagate
  end

  window:trigger('mouse_event', x, y, event)

  if event:match('_click') then
    -- trigger a 'click' event for all mouse clicks
    window:trigger('mouse_event', x, y, 'click')
    if count > 0 and count % 2 == 0 then -- four clicks in a row should count as 2 x double-click
      window:trigger('mouse_event', x, y, 'double_click')
    elseif count > 0 and count % 3 == 0 then -- same as above, but x3
      window:trigger('mouse_event', x, y, 'triple_click')
    end

  elseif event:match('scroll_') then
    -- trigger a 'scroll' event for up/down
    local dir = key == tb.KEY_MOUSE_WHEEL_UP and -3 or 3
    window:trigger('mouse_event', x, y, 'scroll', dir)
  end

end

function on_resize(w, h)
  tb.resize()
  screen.width  = w
  screen.height = h

  -- trigger a 'resize' even on the main window
  -- this will cascade down to child elements, recursively.
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
  until stopped or res == -1
end

function stop()
  stopped = true
end

local ui  = {}
ui.load   = load
ui.unload = unload
ui.start  = start
ui.stop   = stop
ui.render = render
-- ui.bold   = tb.bold

ui.Box        = Box
ui.Label      = Label
ui.TextBox    = TextBox
ui.EditableTextBox = EditableTextBox
ui.List       = List
ui.OptionList = OptionList
ui.Menu       = Menu

return ui