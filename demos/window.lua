local ui = require('demos.lib.ui')
local tb = require('luabox')

local window, header, footer, editor

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

function init()
  window = ui.load({ mouse = true })

  if not window then
    print "Unable to load UI."
    os.exit(1)
  end

  local logo = ui.Label("Bolder", { top = -10, width = "auto", vertical_pos = "center", horizontal_pos = "center" })
  window:add(logo)

  local nice_window = ui.StyledBox({ height = 4, width = 0.65, vertical_pos = "center", horizontal_pos = "center", bg = tb.DARKEST_GREY })

  local top_label = ui.EditableTextBox("", { height = 1, top = 1, left = 3, fg = tb.DARK_GREY, placeholder = "Ask anything" })
  nice_window:add(top_label)

  local bottom_label = ui.Label("Build", { bottom = 0, left = 3, vertical_pos = "bottom" })
  nice_window:add(bottom_label)

  window:add(nice_window)
end


init()
ui.start()
ui.unload()
