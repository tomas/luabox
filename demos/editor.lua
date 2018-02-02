local ui = require('demos.lib.ui')
local tb = require('lua-termbox')

local window, header, footer, editor

function read(file)
  local f = io.open(file, "rb")
  local content = f:read("*all")
  f:close()
  return content
end

function init()
  window = ui.load()

  if not window then
    print "Unable to load UI."
    os.exit(1)
  end

  header = ui.Box({ height = 1, bg = tb.BLUE })
  window:add(header)

  footer = ui.Box({ height = 1, position = "bottom", bg = tb.BLACK })
  window:add(footer)

  editor = ui.EditableTextBox("", { top = 1, bottom = 1 })
  window:add(editor)
end

function open(file)
  local content = read(file)
  editor:set_text(content)
end

init()

if arg[1] then
  open(arg[1])
end

editor:focus()
ui.start()
ui.unload()