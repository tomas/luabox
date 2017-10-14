local ui = require('demos.lib.ui')
local tb = require('termbox')

-----------------------------------------

local window = ui.load()

-- create a 10x10 rectangle at coordinates 5x5
if not window then
  print "Unable to load UI."
  os.exit(1)
end

local header = ui.Box({ height = 1, bg_char = 0x2573 })
window:add(header)

local left = ui.Box({ top = 1, bottom = 1, width = 0.5, bg = ui.light(tb.BLACK) })
window:add(left)

local right = ui.Box({ top = 1, left = 0.5, bottom = 1, width = 0.5, bg = tb.BLUE })
window:add(right)

text = [[
This function returns a formated version
of its variable number of arguments following
the description given in its first argument
(which must be a string). The format string
follows the same rules as the printf family
of standard C functions. The only differencies
are that the options/modifiers * , l , L , n , p ,
and h are not supported, and there is an extra
option, q . This option formats a string in a
form suitable to be safely read back by the
Lua interpreter. The string is written between
double quotes, and all double quotes, returns
and backslashes in the string are correctly
escaped when written.
]]

local para = ui.TextBox(text, { top = 1, left = 1, right = 1 })
right:add(para)

local footer = ui.Box({ height = 1, position = "bottom", bg = tb.BLACK })
window:add(footer)

-- local sidebar = VBox({ x = 2, y = 3, width = 12, bg = tb.RED })
-- window:add(sidebar)

-- local main = VBox({ x = 15, y = 3, width = 30, bg = tb.GREEN })
-- window:add(main)

local label = Label("Latest commits", { left = 1, right = 1, bg = tb.GREEN })
left:add(label)

local items = {
  "Commit 1",
  "Commit 2",
  "Commit 3",
  "Commit 4",
  "Commit 5",
  "Commit 6",
  "Commit 7",
  "Commit 8",
  "Commit 9",
  "Commit 10",
  "Commit 11",
  "Commit 12",
  "Commit 13",
  "Commit 14",
  "Commit 15",
  "Commit 16",
}

local commits = ui.OptionList(items, { top = 1, left = 1, right = 1 })
left:add(commits)

commits:on('selected', function(selected, item)
  -- print(selected, item)
  para.text = "Showing commit: " .. item
end)

ui.start()
ui.unload()
