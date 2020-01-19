local tb      = require('luabox')
local time    = require('demos.lib.time')
local Object  = require('demos.lib.classic')
local Emitter = require('demos.lib.events')
local ustring = require('demos.lib.ustring')

local screen, window, stopped
local box_count = 0
local stopchars = '[ /]'
local cursor_color = tb.RED
local page_move_ratio = 1.3

local function dump(o)
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

local function errwrite(str)
  io.stderr:write(str .. "\n")
end

local function debug(obj)
  errwrite(dump(obj))
end

local function round(num)
  if num >= 0 then return math.floor(num+.5)
  else return math.ceil(num-.5) end
end

local function merge_table(a, b)
  for key, val in pairs(b) do
    a[key] = val
  end
  return a
end

-- local function num_matches(haystack, needle)
--   local count = 0
--   for i in string.gfind(haystack, needle) do
--      count = count + 1
--   end
--   return count
-- end

local function contains_newline(str, stop)
  local subs = str:sub(0, stop)
  return subs:find('\n')
end

-----------------------------------------
-- timers

local timers = {}

-- local function find_timer_by_name(name)
--   for idx, timer in ipairs(timers) do
--     if timer.name and timer.name == name then
--       return timer
--     end
--   end
-- end

local function add_timer(time, fn, repeating, name)
  -- if name and find_timer_by_name(name) then
  --   return
  -- end

  local t = { time = time, fn = fn, name = name, repeating = repeating and time or nil }
  table.insert(timers, t)
  return t
end

local function add_immediate_timer(fn, name)
  return add_timer(0, fn, false, name)
end

local function add_repeating_timer(time, fn, name)
  return add_timer(time, fn, true, name)
end

local function update_timers(last_time)
  local now = (time.time() * 1000)
  local delta = now - last_time
  -- io.stderr:write("now: " .. now .. ", delta: " .. delta .. "\n")

  for idx, timer in ipairs(timers) do
    timer.time = timer.time - delta
    if timer.time <= 0 then
      local res = timer.fn()
      if timer.repeating and not res then
        timer.time = timer.repeating
      else
        table.remove(timers, idx)
      end
    end
  end

  return now
end

local function remove_timer(t)
  for idx, timer in ipairs(timers) do
    if timer == t then
      table.remove(timers, idx)
    end
  end
end

local function clear_timers()
  timers = {}
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

  self.vertical_pos   = opts.vertical_pos   -- top, center or bottom
  self.horizontal_pos = opts.horizontal_pos -- left, center or right

  self.changed  = true
  self.hidden   = opts.hidden or false
  self.shown    = not self.hidden
  self.parent   = nil
  self.children = {}
  self.emitter  = Emitter:new()


  -- self:on('resized', function(new_w, new_h)
  --   self:mark_changed()
  --   for _, child in ipairs(self.children) do
  --     child:trigger('resized', new_w, new_h)
  --   end
  -- end)

  -- cascade events down
  self:on('mouse_event', function(x, y, evt, ...)
    for _, child in ipairs(self.children) do
      if child.shown and child:contains(x, y) then
        child:trigger('mouse_event', x, y, evt, ...)
        child:trigger(evt, x, y, ...)
      end
    end
  end)

  -- lets us tell child windows to redraw based on a x/y cell coord
  self:on('cell_changed', function(x, y)
    for _, child in ipairs(self.children) do
      if child.shown and child:contains(x, y) then
        child:mark_changed()
        child:trigger('cell_changed', x, y)
      end
    end
  end)
end

function Box:__tostring()
  local w, h = self:size()
  return string.format("<Box [w:%d,h:%d] [x:%d/y:%d] [fg:%d,bg:%d]>", w, h, self.x, self.y, self.width or -1, self.height or -1, self.fg or -1, self.bg or -1)
end

function Box:set_width(val)
  self.width = val
  self:trigger('resized')
end

function Box:set_height(val)
  self.height = val
  self:trigger('resized')
end

function Box:set_hidden(bool)
  self.hidden = bool
  self.shown = not bool
  self:trigger(bool and 'hidden' or 'unhidden')
  return bool
end

function Box:mark_changed()
  local was_changed = self.changed
  self.changed = true
  self:trigger('changed')
  return was_changed
end

function Box:toggle(bool)
  self:mark_changed()
  local hidden_val

  if bool == true or bool == false then
    hidden_val = not bool
  elseif self.hidden then
    hidden_val = false
  else
    hidden_val = true
  end

  self:set_hidden(hidden_val)
  return not hidden_val -- true if now shown
end

function Box:unfocus(focus_prev)
  if not window.focused == self then return end

  self:trigger('unfocused')
  self:mark_changed()
  window.focused = nil

  if focus_prev and window.prev_focused then
    window.prev_focused:focus()
  end
end

function Box:focus()
  if self:is_focused() then return end

  -- unfocus whatever box is marked as focused
  -- store previously focused element
  window.prev_focused = window.focused

  -- trigger unfocused for previously focused
  if window.prev_focused then window.prev_focused:unfocus() end

  -- set current focused element to this
  window.focused = self

  -- and trigger 'focused' for newly focused, passsing prev focused as param
  self:trigger('focused', window.prev_focused)
  self:mark_changed()
end

function Box:toggle_focus()
  if self:is_focused() then
    self:unfocus()
  else
    self:focus()
  end
end

function Box:is_focused()
  return window.focused == self
end

function Box:set_bg(color)
  self.bg = color
  self:mark_changed()
end

function Box:set_fg(color)
  self.fg = color
  self:mark_changed()
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

--[[
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
--]]

function Box:margin()
  local parent_w, parent_h = self.parent:size()

  -- raw width to calculate in case the width is %
  local w, h = self.width, self.height
  if w and w < 1 then w = w * parent_w end
  if h and h < 1 then h = h * parent_h end

  local vert_pos = self.vertical_pos
  local horiz_pos = self.horizontal_pos

  local top, right, bottom, left

  -- position "top" is a bit unnecessary, but what the hell.
  if vert_pos == 'center' then
    top    = (parent_h - h)/2
    bottom = (parent_h - h)/2
  else
    top    = vert_pos == "bottom" and (parent_h - (h or 0) - self.bottom) or (self.top >= 1 and self.top or parent_h * self.top)
    bottom = vert_pos == "top" and (parent_h - (h or 0) - self.top) or (self.bottom >= 1 and self.bottom or parent_h * self.bottom)
  end

  if horiz_pos == 'center' then
    left   = (parent_w - w)/2
    right  = (parent_w - w)/2
  else
    left   = horiz_pos == "right" and (parent_w - (w or 0) - self.right) or (self.left >= 1 and self.left or parent_w * self.left)
    right  = horiz_pos == "left" and (parent_w - (w or 0) - self.left) or (self.right >= 1 and self.right or parent_w * self.right)
  end

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
  else -- width not set. parent width minus left/right margins
    w = parent_w - (left + right)
    -- debug({ "width not set", self.id, parent_w, left, right, "result => ", w })
  end

  if self.height then -- height of parent
    h = self.height >= 1 and self.height or parent_h * self.height
  else -- height not set. parent height minus top/bottom margins
    h = parent_h - (top + bottom)
  end

  return w, h
end

function Box:on(evt, fn)
  return self.emitter:on(evt, fn)
end

function Box:once(evt, fn)
  return self.emitter:once(evt, fn)
end

function Box:trigger(evt, ...)
  return self.emitter:emit(evt, ...)
end

function Box:add(child)
  if child.parent then
    errwrite("Child already has a parent!")
    return
  end

  child.parent = self
  table.insert(self.children, child)
  self:trigger('child_added', child)
  self:mark_changed()
  return child
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

function Box:clear_line(x, y, fg, bg, char, width)
  tb.string(x, y, fg, bg, string.rep(char, width))
end

function Box:clear()
  local offset_x, offset_y = self:offset()
  local width, height = self:size()
  local fg, bg = self:colors()
  local rounded_width = math.ceil(width)

  -- debug({ "clearing " .. self.id, offset_x, width })
  for y = 0, math.ceil(height)-1, 1 do
    self:clear_line(offset_x, y + offset_y, fg, bg, self.bg_char, rounded_width)

    -- for x = 0, math.floor(width), 1 do
    --   tb.char(x + offset_x, y + offset_y, fg, bg, self.bg_char)
    -- end
  end
end

function Box:render_self()
  self:clear()
  -- center = math.ceil(height/2)
  -- local top, right, bottom, left = self:margin()
  -- tb.string(offset_x+1, offset_y, fg, bg, string.format("%dx%d @ %dx%d [%d,%d,%d,%d]",
  -- width, height, offset_x, offset_y, top, right, bottom, left, center))
end

-- marks box and children as changed so we force rerendering all
function Box:refresh()
  self:mark_changed()
  for _, child in ipairs(self.children) do
    child:refresh()
  end
end

function Box:rendered()
  self.changed = false
end

function Box:render()
  -- errwrite('rendering ' .. self.id)
  if self.shown then
    if self.changed then
      -- errwrite('changed! ' .. self.id)
      self:render_self()
      self:rendered()
    end
    self:render_tree()
  end
end

function Box:render_tree()
  for _, child in ipairs(self.children) do
    -- if child is current above item, skip rendering
    -- as it will be called after all elements have been drawn
    if window.above_item ~= child then
      child:render()
    end
  end
end

function Box:remove_tree()
  for _, child in ipairs(self.children) do
    child:remove()
  end
end

function Box:remove()
  if self.parent and self.parent.trigger then
    self.parent:trigger('child_removed', self)
  end
  self:remove_tree()
  self.emitter:removeAllListeners()
  self.hidden = true
end

----------------------------------------

local Label = Box:extend()

function Label:new(text, opts)
  local opts = opts or {}
  Label.super.new(self, opts)

  self.height = 1
  if opts.width == 'auto' then
    self.auto_width = true -- so we resize when setting a bigger text
  end
  self:set_text(text)
end

function Label:get_text(text)
  return self.text
end

function Label:set_text(text)
  if self.auto_width and text then
    self:set_width(ustring.len(text))
  end
  self.text = text
  self:mark_changed()
end

function Label:render_self()
  Label.super.render_self(self)

  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()
  if width == 0 or height == 0 then return end

  local str = ustring.sub(self.text, 0, math.floor(width))
  tb.string(x, y, fg, bg, str)
end

----------------------------------------

local TextBox = Box:extend()

function TextBox:new(text, opts)
  TextBox.super.new(self, opts or {})
  self:set_text(text)
  self.nlines = -1 -- unknown

  self:on('left_click', function(mouse_x, mouse_y)
    self:focus()
  end)

  self:on('scroll_up', function(mouse_x, mouse_y)
    self:scroll_up()
  end)

  self:on('scroll_down', function(mouse_x, mouse_y)
    self:scroll_down()
  end)
end

function TextBox:set_text(text)
  self:mark_changed()
  self.text = text or '' -- :gsub("\n", " ")
  self.chars = ustring.len(self.text)
  self.xpos = 0
  self.ypos = 0
end

function TextBox:get_text()
  return self.text
end

function TextBox:scroll_up()
  -- TODO
end

function TextBox:scroll_down()
  -- TODO
end

function TextBox:move_to(ypos)
  if ypos < 0 then ypos = 0 end

  self:mark_changed()
  self.ypos = ypos
end

function TextBox:move(dir)
  local result = math.floor(dir) + self.ypos
  local width, height = self:size()

  -- ensure we stay within bounds
  if result < 0 then
    return self:move_to(0)
  -- and that the don't show an empty box
  elseif dir > 0 and (self.nlines > 0 and result > (self.nlines - height + dir)) then
    return
  end

  self:move_to(result)
end

function TextBox:get_xpos()
  return self.xpos
end

function TextBox:get_ypos()
  return self.ypos
end

function TextBox:render_line(x, y, fg, bg, line)
  tb.string(x, y, fg, bg, line)
end

function TextBox:render_self()
  -- TextBox.super.clear(self)
  self:clear()

  local xpos = self:get_xpos()
  local ypos = self:get_ypos()
  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()
  width = math.floor(width)

  local nlines = 1
  local str, line, linebreak, limit, line_num = self:get_text()
  for line_num = 0, (height+ypos) - 1, 1 do
    if ustring.len(str) <= 0 then break end

    linebreak = string.find(str, '\n')
    if linebreak and linebreak <= width then
      line = ustring.sub(str, 0, linebreak - 1)
      limit = linebreak + 1
    else
      -- check if remaining string is shorter than width
      local diff = width - ustring.len(str)

      if diff > 0 then -- yep, this is the last line
        line = str
      else
        line = ustring.sub(str, 0, round(width))
      end

      limit = width + 1
    end

    if line_num >= ypos then
      self:render_line(x, y + line_num - ypos, fg, bg, line)
    end

    str = ustring.sub(str, limit)
    nlines = nlines + 1
  end

  self.nlines = nlines
end

local EditableTextBox = TextBox:extend()

function EditableTextBox:new(text, opts)
  EditableTextBox.super.new(self, text, opts or {})
  self.placeholder = opts.placeholder

  self:on('key', function(key, char, meta)
    if char == '' or meta > 2 then
      self:handle_key(key, meta)
    else
      self:append_char(char)
    end
    self:mark_changed()
  end)
end

function EditableTextBox:set_placeholder(text)
  self.placeholder = text
  self:mark_changed()
end

function EditableTextBox:get_text()
  if self.placeholder and not self:is_focused() then
  -- if self.placeholder and self.chars == 0 then
    return self.placeholder
  else
    return self.text
  end
end

function EditableTextBox:handle_key(key, meta)
  if key == tb.KEY_ENTER and meta == 0 then
    self:handle_enter()
  elseif key == tb.KEY_BACKSPACE then
    if meta == tb.META_ALT then
      self:delete_last_word()
    else
      self:delete_char(-1)
    end
  elseif key == tb.KEY_DELETE then
    self:delete_char(0)
  elseif key == tb.KEY_HOME then
    self:move_cursor_to_last('\n')
  elseif (key == tb.KEY_CTRL_A and meta == tb.META_CTRL) then
    self.cursor_pos = 0
  elseif key == tb.KEY_END then
    self:move_cursor_to_next('\n')
  elseif (key == tb.KEY_CTRL_E and meta == tb.META_CTRL) then
    self.cursor_pos = self.chars
  elseif key == tb.KEY_ARROW_LEFT then
    if meta == tb.META_CTRL then
      self:move_cursor_to_last(stopchars)
    else
      self:move_cursor_left()
    end
  elseif key == tb.KEY_ARROW_RIGHT then
    if meta == tb.META_CTRL then
      self:move_cursor_to_next(stopchars)
    else
      self:move_cursor_right()
    end
  elseif key == tb.KEY_ARROW_DOWN then
    self:move_cursor_down()
  elseif key == tb.KEY_ARROW_UP then
    self:move_cursor_up()
  end
end

function EditableTextBox:move_cursor(dir)
  local res = self.cursor_pos + dir

  if res < 0 or res > self.chars then
    return
  end

  self.cursor_pos = res
end

function EditableTextBox:move_cursor_left()
  return self:move_cursor(-1)
end

function EditableTextBox:move_cursor_right()
  return self:move_cursor(1)
end

function EditableTextBox:maybe_move_cursor_up()
  local cursor_x, cursor_y = self:get_cursor_offset()
  if cursor_y == 0 and self.ypos > 0 then
    self:move(-1)
    return
  end
end

function EditableTextBox:move_cursor_up()
  if self:maybe_move_cursor_up() then
    return true
  end

  local width, height = self:size()
  if not self:move_cursor(math.floor(width) * -1) then
    self:move_cursor_to_last('\n')
  end
end

function EditableTextBox:maybe_move_cursor_down()
  local width, height = self:size()

  local cursor_x, cursor_y = self:get_cursor_offset()

  if cursor_y >= height and self.nlines >= height then
    self:move(1)
    return true
  end
end

function EditableTextBox:move_cursor_down()
  if self:maybe_move_cursor_down() then
    return true
  end

  local width, height = self:size()
  if not self:move_cursor(math.floor(width)) then
    self:move_cursor_to_next('\n')
  end
end

function EditableTextBox:move_cursor_to_beginning()
  self.cursor_pos = 0
end

function EditableTextBox:move_cursor_to_end()
  self.cursor_pos = self.chars
end

function EditableTextBox:move_cursor_to_last(char)
  local reverse_cursor_pos = self.chars - self.cursor_pos
  local lastpos = string.find(self.text:reverse(), char, reverse_cursor_pos+2)
  if lastpos and lastpos - reverse_cursor_pos > 0 then
    self:move_cursor(-(lastpos - reverse_cursor_pos - 1))
  else
    self:move_cursor_to_beginning()
  end
end

function EditableTextBox:move_cursor_to_next(char, insert_after)
  local nextpos = string.find(self.text, char, self.cursor_pos+2)
  local offset = insert_after and 0 or -1
  self.cursor_pos = nextpos and (nextpos + offset) or self.chars
end

function EditableTextBox:handle_enter()
  self:append_char('\n')
  self:maybe_move_cursor_down()
end

function EditableTextBox:set_text(text)
  EditableTextBox.super.set_text(self, text)
  self.cursor_pos = self.chars
end

function EditableTextBox:append_char(char)
  if self.cursor_pos == self.chars then
    self.text = self.text .. char
  else
    self.text = ustring.sub(self.text, 0, self.cursor_pos) .. char .. ustring.sub(self.text, self.cursor_pos + 1)
  end

  self.chars = self.chars + 1
  self:move_cursor(1)
end

function EditableTextBox:delete_char(at)
  if (self.cursor_pos == 0 and at < 0) or (self.cursor_pos == self.chars and at >= 0) then
    return false
  end

  if self.cursor_pos == self.chars then
    self.text = ustring.sub(self.text, 0, self.chars + at)
  else
    self.text = ustring.sub(self.text, 0, self.cursor_pos + at) .. ustring.sub(self.text, self.cursor_pos + (at + 2))
  end

  self.chars = self.chars - 1
  self:move_cursor(at)
  self:maybe_move_cursor_up()

  return true
end

function EditableTextBox:delete_last_word()
  local deleting = true
  while deleting do
    if self:delete_char(-1) == false or string.find(self:get_char_at_pos(self.cursor_pos), stopchars) == 1 then
      deleting = false
    end
  end
end

function EditableTextBox:get_cursor_offset(width)
  if not width then
    local w, h = self:size()
    width = round(w)
  end

  local pos = self.cursor_pos
  local str = ustring.sub(self.text, 0, pos)

  if pos < width and not contains_newline(str, width-1) then
    return pos, 0
  end

  local x, y, line = 0, 0, nil
  local n, chars, limit, nextbreak = 0, 0, 0
  while ustring.len(str) > 0 do

    nextbreak = string.find(str, '\n')
    if nextbreak and nextbreak <= width then
      line  = ustring.sub(str, 0, nextbreak-1)
      limit = nextbreak + 1
      chars = chars + nextbreak
    else
      line = ustring.sub(str, 0, width)
      limit = width + 1
      chars = chars + width
    end

    n = n + 1
    str = ustring.sub(str, limit)
    -- debug(string.format("chars: %d, pos: %d, width: %d, break: %d, line len: %d", chars, pos, width, nextbreak or '-1', line:len()))

    if chars == pos then
      y = n
      x = 0
      break
    elseif (chars < pos and chars + ustring.len(line) > pos) then
      if not contains_newline(str, pos - chars) then
        y = n
        x = pos - chars
        break
      end
    elseif chars > pos then
      y = n-1
      x = ustring.len(line)
      break
    end
  end

  return x, (y - self:get_ypos())
end

function EditableTextBox:get_char_at_pos(pos)
  return ustring.sub(self.text, pos, pos)
end

function EditableTextBox:render_cursor()
  local x, y = self:offset()
  local fg, bg = self:colors()
  local width, height = self:size()

  local cursor_x, cursor_y = self:get_cursor_offset(math.floor(width))
  local char = self:get_char_at_pos(self.cursor_pos+1)

  if cursor_y >= height then
    return -- don't render cursor, we're off limits
  end

  tb.string(x + cursor_x, y + cursor_y, fg, cursor_color, (char == '' or char == '\n') and ' ' or char)
end

function EditableTextBox:render_self()
  EditableTextBox.super.render_self(self)
  if self:is_focused() then
    self:render_cursor()
  end
end

-----------------------------------------

local TextInput = EditableTextBox:extend()

function TextInput:new(opts)
  TextInput.super.new(self, "", opts)
  self.height = 1
  self.placeholder = opts.placeholder
end

function TextInput:handle_enter()
  self:trigger('submit', self.text)
end

function TextInput:move_cursor(dir)
  local w, h = self:size()
  if dir > 0 and self.chars > w then
    self.xpos = self.chars - w
  elseif dir < 0 and self.xpos > 0 then
    self.xpos = self.chars - w
  else
    TextInput.super.move_cursor(self, dir)
  end
end

-- function TextInput:move_cursor_left()
--   return self:move_cursor(-1)
-- end

-- function TextInput:move_cursor_right()
--   return self:move_cursor(1)
-- end

-----------------------------------------

local List = Box:extend()

function List:new(items, opts)
  List.super.new(self, opts or {})

  self.ypos = 1
  self.selected = 0
  self.items = items or {}
  self.nitems = table.getn(self.items)

  self.selection_fg = opts.selection_fg
  self.selection_bg = opts.selection_bg or tb.BLACK

  self.focus_selection_fg = opts.focus_selection_fg or self.selection_fg
  self.focus_selection_bg = opts.focus_selection_bg or self.selection_bg

  self.changed_line_from = nil
  self.changed_line_to = nil

  self:on('left_click', function(mouse_x, mouse_y)
    self:focus()
  end)

  self:on('key', function(key, ch, meta)
    -- self:mark_changed()
    local w, h = self:size()

    if key == tb.KEY_ARROW_DOWN or (ch == 'j' and meta == 0) then
      self:move(1)
    elseif key == tb.KEY_ARROW_UP or (ch == 'k' and meta == 0) then
      self:move(-1)
    elseif key == tb.KEY_HOME then
      self:move_to(1, 1)
    elseif key == tb.KEY_END then
      if self:num_items() > 0 then -- known item count
        if self:num_items() > h then
          self:move_to(self:num_items() - (math.floor(h) - 2))
        end
        self:set_selected_item(self:num_items(), true)
      else -- unknown, just forward one page
        self:move_page(1, h)
      end
    elseif key == tb.KEY_PAGE_DOWN and meta == 0 then
      self:page_down(h)
    elseif key == tb.KEY_PAGE_UP and meta == 0 then
      self:page_up(h)
    end
  end)

  self:on('scroll', function(x, y, dir)
    self:move(dir)
  end)
end

function List:is_visible(ypos)
  local width, height = self:size()
  return ypos > self.ypos and ypos < self.ypos + height
end

function List:set_ypos(ypos)
  -- self:mark_changed()
  self.ypos = ypos
end

function List:move_to(ypos, selected_pos)
  -- if ypos > self:num_items() then 
  --   ypos = self:num_items()
  -- end
  if ypos < 1 then ypos = 1 end

  -- ensure we trigger a full refresh on next render loop
  self.changed_line_from = nil
  self.changed_line_to = nil

  -- make sure to mark changed before calling set_selected_item
  -- so we don't just mark the specific changed lines
  self:mark_changed()
  self:set_ypos(ypos)

  if selected_pos then
    self:set_selected_item(selected_pos, true)
  end
end

function List:move(dir)
  local result = math.floor(dir) + self.ypos
  local width, height = self:size()
  local nitems = self:num_items()

  -- ensure we stay within bounds
  if result < 1 then
    return self:move_to(1)
  -- and that the don't show an empty box
  elseif dir > 0 and (nitems > 0 and result > (nitems - height + dir)) then
    return
  end

  self:move_to(result)
end

function List:page_up(height)
  return self:move_page(-1, height)
end

function List:page_down(height)
  return self:move_page(1, height)
end

function List:move_page(dir, height)
  local lines = math.floor(height/page_move_ratio) * dir
  local cur = self.selected
  self:move(lines)

  local new_sel = cur + lines < 1 and 1 or cur + lines
  self:set_selected_item(new_sel, true)
end

function List:num_items()
  return self.nitems
end

function List:clear_items()
  self:set_items({}, true)
end

function List:set_items(arr, reset_position)
  self.items = arr
  self.nitems = table.getn(self.items)
  self:mark_changed()
  if reset_position then
    self:set_ypos(1)
    self:set_selected_item(0, false)
  else
    if self.selected > self:num_items() then
      self:set_selected_item(self:num_items())
    end
    if self.ypos > self:num_items() then
      self:move_to(self:num_items())
    end
  end
end

function List:set_item(number, item)
  self.items[number] = item
  -- we might be adding a new item, so recalc
  self.nitems = table.getn(self.items)
end

function List:add_item(item)
  self:set_item(self.nitems + 1, item)
end

function List:get_item(number)
  return self.items[number]
end

function List:set_selected_item(number, trigger_event)
  local nitems = self:num_items()

  if nitems > 0 and number > nitems then
    number = nitems
  end

  if number and not self.changed then
    self.changed_line_from = self.selected
    self.changed_line_to = number
  else
    self.changed_line_from = nil
    self.changed_line_to = nil
  end

  self:mark_changed()
  self.selected = number

  if trigger_event then
    self:trigger('selected', number, self:get_item(number))
  end
end

function List:get_selected_item()
  return self:get_item(self.selected), self.selected
end

function List:format_item(item)
  return tostring(item)
end

function List:fix_encoding(str)
  if ustring.emojiCount(str) > 0 then
    return ustring.replaceEmoji(str, ' ')
  else
    return str
  end
end

function List:item_fg_color(index, item, default_color)
  if index == self.selected then
    return self:is_focused() and self.focus_selection_fg or self.selection_fg or default_color
  else
    return default_color
  end
end

function List:item_bg_color(index, item, default_color)
  if index == self.selected then
    return self:is_focused() and self.focus_selection_bg or self.selection_bg or default_color
  else
    return default_color
  end
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

function List:render_item(formatted, x, y, fg, bg)
  -- debug({ " --> line " .. index , formatted })
  tb.string(x, y, fg, bg, formatted)
end

function List:render_self()
  if not self.changed_line_from then
    self:clear()
  end

  local x, y = self:offset()
  local width, height = self:size()
  local fg, bg = self:colors()
  local rounded_width = width % 1 == 0 and width or math.floor(width)+1
  local index, item, formatted, diff, skip_render

  -- if horizontal pos is right, then align text to the right and move X offset
  local align_right = self.horizontal_pos == 'right'

  for line = 0, math.ceil(height)-1, 1 do
    index = line + self.ypos
    skip_render = false

    if self.changed_line_from and self.changed_line_to then --
      if index == self.changed_line_from or index == self.changed_line_to then
        self:clear_line(x, y + line, fg, bg, self.bg_char, width)
      else
        -- not one of the changed lines, so skip
        skip_render = true
      end
    end

    if not skip_render then
      item = self:get_item(index)
      if not item then break end

      formatted = self:format_item(item)
      final     = self:fix_encoding(formatted)
      diff      = width - ustring.len(final)

      if diff >= 0 then -- line is shorter than width
        final = final -- .. string.rep(' ', diff)
      else -- line is longer, so cut!
        final = ustring.sub(final, 0, rounded_width-1) .. '…'
        diff = 0
      end

      self:render_item(final, align_right and (x + diff) or x, y + line, self:item_fg_color(index, item, fg), self:item_bg_color(index, item, bg))
    end
  end

  self.changed_line_from = nil
  self.changed_line_to = nil
end

-----------------------------------------

local OptionList = List:extend()

function OptionList:new(items, opts)
  OptionList.super.new(self, items, opts)

  self:on('key', function(key, ch, meta)
    if ch == ' ' or (key == tb.KEY_ENTER and meta == 0) then -- space or enter
      self:submit()
    end
  end)

  self:on('left_click', function(mouse_x, mouse_y)
    local x, y = self:offset()
    self:select(self.ypos + (mouse_y - y))
  end)

  self:on('double_click', function(mouse_x, mouse_y)
    self:submit()
  end)
end

function OptionList:move(dir)
  local nitems = self:num_items()
  local new_selected = self.selected + dir

  if new_selected < 1 then
    new_selected = 1
  elseif nitems > 0 and new_selected > nitems then
    new_selected = nitems
  end

  local width, height = self:size()

  -- if new_selected is above position or below position + height, then also move
  if new_selected < self.ypos or (new_selected >= self.ypos + height) then
    OptionList.super.move(self, dir)
  end

  return self:set_selected_item(new_selected, true)
end

function OptionList:select(number, clamp)
  if clamp then
    if number < 1 then
      number = 1
    else
      local nitems = self:num_items()
      if nitems and nitems > 0 and number > nitems then
        number = nitems
      end
    end
  end

  -- check if within bounds and actually changed
  local item = self:get_item(number)
  if not item then return end

  if number ~= self.selected then
    self:set_selected_item(number, true)
  end

  return item
end

function OptionList:submit()
  local item = self:get_selected_item()
  if item then
    self:trigger('submit', self.selected, item)
  end
end

-----------------------------------------

local Menu = OptionList:extend()

function Menu:new(items, opts)
  Menu.super.new(self, items, opts)

  self.min_width = opts.min_width
  self.max_width = opts.max_width

  local hidden = opts.hidden == nil and true or opts.hidden
  self:set_hidden(hidden)

  -- selected is triggered on left click
  self:on('left_click', function(index, item)
    self:submit()
  end)

  -- hide menu on submit
  -- update: no need to. window.hide_above will do this for us
  -- self:on('submit', function(index, item)
  --   self:toggle(false)
  -- end)
end

function Menu:set_offset(x, y)
  self.offset_x = x
  self.offset_y = y
end

function Menu:offset()
  if self.offset_x and self.offset_y then
    return self.offset_x, self.offset_y
  else
    local x, y = Menu.super.offset(self)
    if self.horizontal_pos == 'right' then
      local w, h = self:size()
      x = x - w -- move offset position
    end
    return x, y
  end
end

function Menu:get_longest_item()
  local res, formatted
  for _, item in ipairs(self.items) do
    formatted = self:format_item(item)
    if not res or ustring.len(formatted) > ustring.len(res) then
      res = formatted
    end
  end

  return res
end

function Menu:size()
  local num_items = self:num_items()
  if num_items == 0 then
    return 0, 0
  end

  local w = self.width
  local h = self.height

  if not h or h > num_items then
    h = num_items
  end

  if not w then
    local item = self:get_longest_item()
    if item then
      w = string.len(item)
      if self.min_width and w < self.min_width then
        w = self.min_width
      elseif self.max_width and w > self.max_width then
        w = self.max_width
      end
    end
  end

  return w, h
end

-----------------------------------------

local SmartMenu = Box:extend()

function SmartMenu:new(items, opts)
  local default_placeholder = ' Choose one '
  local width = opts.width or (string.len(opts.placeholder or default_placeholder))

  local box_opts = {
    hidden = opts.hidden,
    width = width,
    top = opts.top or 0,
    left = opts.left,
    right = opts.right,
    height = 1,
    horizontal_pos = opts.horizontal_pos
  }

  SmartMenu.super.new(self, box_opts)

  self.original_items = items
  self.selected_item = 0
  self.revealed = false

  self.input = TextInput({
    placeholder = opts.placeholder or default_placeholder,
    bg = opts.bg or tb.WHITE,
    fg = opts.fg or tb.BLACK,
    height = 1,
    -- horizontal_pos = opts.horizontal_pos
  })

  self:add(self.input)

  local menu_height = opts.height and opts.height - 1 or nil
  local menu_bg = opts.menu_bg or tb.GREY

  self.menu = Menu(items, {
    horizontal_pos = opts.horizontal_pos,
    min_width = width,
    max_width = width * 2,
    height = menu_height,
    bg = menu_bg,
    fg = opts.menu_fg,
    selection_fg = opts.menu_selection_fg,
    selection_bg = opts.menu_selection_bg or menu_bg,
    top = 1,
    -- bottom = 0
  })

  self:add(self.menu)

  -- self.input:on('focused', function()
  --   self:reveal()
  -- end)

  self.input:on('left_click', function()
    self:reveal()
  end)

  -- hidden is triggered via window:hide_above(self.menu)
  -- self.closed ensures the smart menu is marked as not revealed
  self.menu:on('hidden', function()
    self:closed()
  end)

  self.menu:on('submit', function(number, value)
    self:select_option(value)
  end)

  self.input:on('submit', function(value)
    if self.revealed then self:select_option(self.menu:get_selected_item()) end
  end)

  self.input:on('key', function(key, ch, meta)
    if key == tb.KEY_ESC then
      self:close()
      -- self.menu:focus()
    elseif key == tb.KEY_ARROW_DOWN then
      self:reveal()
      self:set_selected_item(1)
    elseif key == tb.KEY_ARROW_UP then
      self:reveal()
      self:set_selected_item(-1)
    elseif key == tb.KEY_TAB then -- or key == tb.KEY_ENTER then
      if self.revealed then
        self.input:set_text(self.menu:get_selected_item())
      end
    elseif ch then
      if not self.revealed then
        self:reveal(self.input:get_text())
      end
      self:filter_options()
    end
  end)
end

function SmartMenu:size()
  local w, h = SmartMenu.super.size(self)
  local menu_w, menu_h = self.menu:size()
  return w, h + menu_h
end

function SmartMenu:set_width(val)
  SmartMenu.super.set_width(self, val)
  self.input:set_width(val)
  self.menu.min_width = val
end

function SmartMenu:set_height(val)
  self.menu:set_height(val)
end

function SmartMenu:set_items(items)
  self.original_items = items
  self.menu:set_items(items)
end

function SmartMenu:set_placeholder(text)
  self.input:set_placeholder(text)
  self:mark_changed()
end

function SmartMenu:reset()
  self.input:set_text('')
  self.selected_item = 0
  self:set_options(self.original_items)
end

function SmartMenu:reveal()
  if self.revealed then return false end
  self.revealed = true

  window:show_above(self.menu)
  self:reset()
  self.input:focus()

  if self.selected_item == 0 then self:set_selected_item() end
  self:trigger('revealed')
end

function SmartMenu:close()
  if not self.revealed then return end

  -- self:reset()
  window:hide_above(self.menu)
end

function SmartMenu:closed()
  self.input:unfocus()
  self.revealed = false
  self:trigger('closed')
end

function SmartMenu:set_selected_item(dir)
  local w, h = self.menu:size()
  local x, y = self.menu:offset()

  if dir then
    local res = self.selected_item + dir
    if res < 1 or res > self.menu:num_items() then return end

    if res > h then
      self.menu:move(1)
    elseif res < h then
      self.menu:move(-1)
    end

    self.selected_item = res
  else
    self.selected_item = 1
  end

  self.menu:set_selected_item(self.selected_item)
end

-- TODO: optimize this
function SmartMenu:select_option(value)
  self.input:set_placeholder(value)
  add_timer(80, function()
    self:close()
  end)

  -- self.input:focus()
  self:trigger('selected', value)
end

function SmartMenu:set_options(arr)
  self.menu:set_items(arr)
  self.menu:move_to(1, 1)

  self.parent:mark_changed()
  self:mark_changed()

  self:trigger('options_changed')

  -- if table.getn(arr) == 0 then -- empty
    -- self.parent:mark_changed()
  -- end
end

function SmartMenu:filter_options(str)
  local str = str or self.input:get_text()

  local arr = {}
  for _, item in ipairs(self.original_items) do
    if string.find(item:lower(), str:lower()) then table.insert(arr, item) end
  end

  self:set_options(arr)
end

-----------------------------------------
-- load/unload UI

local function load(opts)
  local opts = opts or {}

  if not tb.init() then return end
  if opts.mouse then tb.enable_mouse() end
  tb.hide_cursor()

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
      if self.above_item == item then return end
      self:hide_above()
    end

    if not item.parent then
      self:add(item)
      item:once('hidden', function()
        item:remove()
      end)
    end

    -- store a reference to the focused window before showing
    -- the above item. note that this is NOT the same as prev_focused
    -- since prev_focused changes whenever a box/label/input is clicked 
    -- and we want to return focused to the original element we had
    -- before showing the above item.
    self.focused_below = self.focused
    self.above_item = item
    item:toggle(true)
    item:focus()
  end

  window.hide_above = function(self, item)
    if not self.above_item then return end

    if item and self.above_item ~= item then
      return -- item was passed, and current above item doesn't match
    end

    -- this triggers 'hidden' which will remove the element 
    -- if it didn't have a parent when show_above() was called
    self.above_item:toggle(false) 

    if self.focused_below then
      self.focused_below:focus()
      self.focused_below = nil
    elseif self.focused == self.above_item then
      self.focused:unfocus()
    end

    -- self:remove(above_item)
    self.above_item = nil
    self:refresh() -- force redraw of child elements
  end

  window.toggle_above = function(self, item)
    if self.above_item then
      self:hide_above(item)
      return false
    else
      self:show_above(item)
      return true
    end
  end

  window.alert = function(self, msg, opts, cb)
    if type(opts) == 'function' then
      cb = opts
      opts = {}
    else
      if opts == nil then opts = {} end
    end
    opts.skip_confirm = true
    self:confirm(msg, opts, cb)
  end

  window.confirm = function(self, msg, opts, cb)
    if type(opts) == 'function' then
      cb = opts
      opts = {}
    else
      if opts == nil then opts = {} end
    end

    local box = Box(merge_table(opts, { hidden = true, bg = tb.LIGHT_GREY, horizontal_pos = "center", vertical_pos = "center", height = 4, width = 0.3 }))
    local label = Label(msg, { left = 2, right = 2, top = 1 })
    box:add(label)

    -- buttons
    local accepted = false
    local button_opts = { bg = tb.DARK_GREY, fg = tb.WHITE, vertical_pos = "bottom", bottom = 0 }

    if opts.skip_confirm then
      button_opts.right = 1
    else
      button_opts.width = 0.4
    end

    local accept = Label(opts.skip_confirm and ' OK ' or ' Yes ', merge_table(button_opts, { width = 5, left = 2 }))
    box:add(accept)

    accept:once('left_click', function()
      accepted = true
      self:hide_above(box)
    end)

    if not opts.skip_confirm then
      -- local cancel = Label(' No ', merge_table(button_opts, { horizontal_pos = "right", width = 4, right = 2 }))
      local cancel = Label(' No ', merge_table(button_opts, { width = 4, left = 8 }))
      box:add(cancel)

      cancel:once('left_click', function()
        window:hide_above(box)
      end)
    end

    self:show_above(box)
    if not cb then return end

    box:once('hidden', function()
      cb(accepted)
    end)
  end

  window.parent = screen
  return window
end

local function unload()
  if window then
    window:remove()
    window = nil
    -- tb.show_cursor()
    tb.shutdown()
  end
end

-----------------------------------------
-- event handling

-- we go from more specific (box, key) to less specific
local function on_key(key, char, meta)
  if window.focused then
    window.focused:trigger('key:' .. key, key, char, meta)
  end

  if window.focused then -- might have been unfocused by previous call
    window.focused:trigger('key', key, char, meta)
  end

  window:trigger('key:' .. key, key, char, meta)
  window:trigger('key', key, char, meta)
end

local mouse_events = {
  [tb.KEY_MOUSE_LEFT]       = 'left_click',
  [tb.KEY_MOUSE_MIDDLE]     = 'middle_click',
  [tb.KEY_MOUSE_RIGHT]      = 'right_click',
  -- [tb.KEY_MOUSE_RELEASE]    = 'mouseup',
  [tb.KEY_MOUSE_WHEEL_UP]   = 'scroll_up',
  [tb.KEY_MOUSE_WHEEL_DOWN] = 'scroll_down'
}

local function on_click(key, x, y, count, is_motion)
  local event = mouse_events[key]
  if not event then return false end

  if is_motion then return end

  if window.above_item then
    if window.above_item:contains(x, y) then
      window.above_item:trigger(event, x, y)
      window.above_item:trigger('mouse_event', x, y, event)
    else
      window:hide_above()
    end
    return -- we don't want to propagate
  end

  window:trigger('mouse_event', x, y, event, is_motion)

  if event:match('_click') then
    -- trigger a 'click' event for all mouse clicks, regardless of button
    window:trigger('mouse_event', x, y, 'click')

    if count > 0 and count % 2 == 0 then -- four clicks in a row should count as 2 x double-click
      window:trigger('mouse_event', x, y, 'double_click')
    elseif count > 0 and count % 3 == 0 then -- same as above, but x3
      window:trigger('mouse_event', x, y, 'triple_click')
    end

  elseif event:match('scroll_') then
    -- trigger a 'scroll' event for up/down
    local dir = key == tb.KEY_MOUSE_WHEEL_UP and -5 or 5
    window:trigger('mouse_event', x, y, 'scroll', dir)
  end

end

local function on_resize(w, h)
  if w > screen.width or h > screen.height then
    tb.resize()
  end

  add_immediate_timer(function()
    screen.width  = w
    screen.height = h

    -- trigger a 'resize' even on the main window
    -- this will cascade down to child elements, recursively.
    window:trigger('resized', w, h)
    window:refresh()
  end, 'resize')
end

-----------------------------------------
-- loop start/stop/render

local function render()
  window:render()
  if window.above_item then
    window.above_item:render()
  end
  tb.render()
end

local function start()
  local res, ev, last_loop = nil, {}, (time.time() * 1000)
  repeat
    last_loop = update_timers(last_loop)
    render()
    res = tb.peek_event(ev, 100)

    if res == tb.EVENT_KEY then
      if ev.key == tb.KEY_ESC and window.above_item then
        window:hide_above()
      else
        if ev.key == tb.KEY_CTRL_C or ev.key == tb.KEY_CTRL_Q then break end
        on_key(ev.key, ev.ch, ev.meta)
      end

    elseif res == tb.EVENT_MOUSE then
      on_click(ev.key, ev.x, ev.y, ev.clicks, ev.meta == 9)

    elseif res == tb.EVENT_RESIZE then
      on_resize(ev.w, ev.h)
    end

  until stopped or res == -1
  clear_timers()
end

local function stop()
  stopped = true
end

local ui  = {}
ui.tb     = tb -- for constants (eg. tb.BLACK, tb.BOLD)
ui.load   = load
ui.unload = unload
ui.start  = start
ui.stop   = stop
ui.render = render

-- timers
ui.after  = add_timer -- ui.after(100, do_something())
ui.next_tick = add_immediate_timer
ui.every  = add_repeating_timer
ui.cancel = remove_timer

ui.Box        = Box
ui.Label      = Label
ui.TextBox    = TextBox
ui.EditableTextBox = EditableTextBox
ui.TextInput = TextInput
ui.List       = List
ui.OptionList = OptionList
ui.Menu       = Menu
ui.SmartMenu  = SmartMenu

return ui
