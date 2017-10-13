local ui = require('demos.lib.ui')
local tb = require('termbox')

-----------------------------------------

local window = ui.load()

-- create a 10x10 rectangle at coordinates 5x5
if not window then
  print "Unable to load UI."
  os.exit(1)
end

local header = ui.Box({ height = 2, bg = tb.BLUE })
window:add(header)

local left = ui.Box({ top = 2, bottom = 1, width = 0.5, bg = tb.GREEN })
window:add(left)

local right = ui.Box({ left = 0.5, top = 2, bottom = 1, width = 0.5, bg = tb.YELLOW })
window:add(right)

local footer = ui.Box({ height = 1, position = "bottom", bg = tb.RED })
window:add(footer)

-- local sidebar = VBox({ x = 2, y = 3, width = 12, bg = tb.RED })
-- window:add(sidebar)

-- local main = VBox({ x = 15, y = 3, width = 30, bg = tb.GREEN })
-- window:add(main)

local label = Label("Unstaged", { left = 1, right = 1 })
left:add(label)

-- local clicks = 0
-- window:on('click', function()
--   clicks = clicks + 1
--   label.text = string.format("Click %d", clicks)
-- end)

ui.start()
ui.unload()
