local ui = require('demos.lib.ui')
local tb = require('luabox')

local window, header, footer, editor

function read(file)
  local f = io.open(file, "rb")
  local content = f:read("*all")
  f:close()
  return content
end

function init()
  window = ui.load({ mouse = true })

  if not window then
    print "Unable to load UI."
    os.exit(1)
  end

  header = ui.Box({ height = 1, bg = tb.GREY })
  window:add(header)
  header:add(ui.Label("Editor"))

  editor = ui.EditableTextBox("", { fg = tb.LIGHT_GREY, focus_fg = tb.WHITE, flexGrow = 1 })
  window:add(editor)

  footer = ui.Box({ height = 1, marginTop = "auto", bg = tb.BLACK })
  window:add(footer)
  footer.label = ui.Label("", { width = "auto" })
  footer:add(footer.label)

end

function open(file)
  local content = read(file)
  if content and content:len() > 0 then
    editor:set_text(content)
    return true
  end
end

init()

if arg[1] and open(arg[1]) then
  footer.label:set_text(arg[1])
else
  footer.label:set_text("New file")
end

editor:focus() 
ui.start()
ui.unload()