local tb = require('luabox')

if not tb.init() then
  print("FAIL: tb_init")
  return
end

local cell = {}
cell.ch = ' '
cell.fg = tb.WHITE
cell.bg = tb.GREEN

tb.string(1, 1, tb.RED, tb.WHITE, "Foobar")
tb.char(5, 5, tb.RED, tb.WHITE, 'X') -- no return val
tb.cell(3, 2, cell)
tb.render() -- no return val

local t, et = {}, nil
repeat
  et = tb.peek_event(t, 1000)
  if et == tb.EVENT_KEY then
    tb.char(5, 5, tb.WHITE, tb.YELLOW, 'K')
  elseif et == tb.EVENT_RESIZE then
    tb.char(5, 5, tb.WHITE, tb.BLUE, 'R')
  else
    tb.char(5, 5, tb.WHITE, tb.RED, 'X')
  end
  tb.render()

  if t.ch == 'q' then break end
until not et

-- wait for ANY event
-- tb.clear()
-- tb.present()
-- tb.poll_event(t)

tb.shutdown() -- no return val

