local ui = require('demos.lib.ui')
local tb = require('lua-termbox')

-----------------------------------------

local window = ui.load()

-- create a 10x10 rectangle at coordinates 5x5
if not window then
  print "Unable to load UI."
  os.exit(1)
end

local header = ui.Box({ height = 1, bg_char = 0x2573 })
window:add(header)

local left = ui.Box({ top = 1, bottom = 1, width = 0.6, bg = tb.DARKER_GREY })
window:add(left)

local right = ui.Box({ top = 1, left = 0.6, bottom = 1, width = 0.4, bg = tb.DARK_GREY })
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
escaped when
written.]]

text = "This is a long text with a new line somewhere\nin between."

-- text = "This function returns a formated version of its variable number of arguments following the description given in its first argument (which must be a string). The format string follows the same rules as the printf family of standard C functions. The only differencies are that the options/modifiers * , l , L , n , p , and h are not supported, and there is an extra option, q . This option formats a string in a form suitable to be safely read back by the Lua interpreter. The string is written between double quotes, and all double quotes, returns and backslashes in the string are correctly escaped when written."

local para = ui.EditableTextBox(text, { top = 1, left = 1, right = 1, focus_fg = tb.WHITE })
right:add(para)

local footer = ui.Box({ height = 1, position = "bottom", bg = tb.BLACK })
window:add(footer)

local label = ui.Label("Some list", { left = 1, right = 1, bg = tb.GREEN })
left:add(label)

local editor = ui.EditableTextBox("Foo bar text", { left = 1, right = 1, top = 2, focus_fg = tb.rgb(0xFFCC00) })
left:add(editor)

para:focus()
ui.start()
ui.unload()
