local ui = require('demos.lib.ui')
local tb = require('termbox')

-----------------------------------------

local window = ui.load()

-- create a 10x10 rectangle at coordinates 5x5
if not window then
  print "Unable to load UI."
  os.exit(1)
end

local header = ui.Box({ top = 1, height = 3, bg_char = '_', bg = tb.BLUE })
window:add(header)

header:on('click', function()
  -- header.bg = tb.RED
end)

local body = ui.Box({ left = 0.5, right = 1, top = 5, width = 0.5, bottom = 1, bg_char = 'x', bg = tb.GREEN })
window:add(body)

body:on('click', function()
  -- body.bg = tb.RED
end)


-- local sidebar = VBox({ x = 2, y = 3, width = 12, bg = tb.RED })
-- window:add(sidebar)

-- local main = VBox({ x = 15, y = 3, width = 30, bg = tb.GREEN })
-- window:add(main)

-- local label = Label("Foobar", { x = 1 })
-- sidebar:add(label)

-- local clicks = 0
-- window:on('click', function()
--   clicks = clicks + 1
--   label.text = string.format("Click %d", clicks)
-- end)

ui.start()
ui.unload()
