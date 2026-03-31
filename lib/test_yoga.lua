-- test_yoga.lua
-- Test suite for yoga-layout Lua port

local yoga = require("yoga")

-- ----------------------------------------------------------------------
-- Simple test runner
-- ----------------------------------------------------------------------
local tests_passed = 0
local tests_failed = 0

local function test(name, fn)
    io.write(string.format("Testing %-50s ", name))
    local ok, err = pcall(fn)
    if ok then
        print("[OK]")
        tests_passed = tests_passed + 1
    else
        print("[FAIL]")
        print("  " .. tostring(err))
        tests_failed = tests_failed + 1
    end
end

local function assert_equal(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function assert_approx(actual, expected, epsilon, msg)
    epsilon = epsilon or 1e-6
    if math.abs(actual - expected) > epsilon then
        error(string.format("%s: expected %s (within %s), got %s", msg, tostring(expected), tostring(epsilon), tostring(actual)))
    end
end

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------
local function set_style(node, style)
    for k, v in pairs(style) do
        local method = node["set" .. k]
        if method then
            method(node, v)
        else
            error("Unknown style property: " .. k)
        end
    end
end

local function assert_layout(node, expected_left, expected_top, expected_width, expected_height, msg)
    local l = node:getComputedLayout()
    assert_approx(l.left, expected_left, 1e-5, msg .. ": left")
    assert_approx(l.top, expected_top, 1e-5, msg .. ": top")
    assert_approx(l.width, expected_width, 1e-5, msg .. ": width")
    assert_approx(l.height, expected_height, 1e-5, msg .. ": height")
end

local function assert_margin(node, edge, expected)
    local actual = node:getComputedMargin(edge)
    assert_approx(actual, expected, 1e-5, "Margin " .. tostring(edge))
end

local function assert_padding(node, edge, expected)
    local actual = node:getComputedPadding(edge)
    assert_approx(actual, expected, 1e-5, "Padding " .. tostring(edge))
end

local function assert_border(node, edge, expected)
    local actual = node:getComputedBorder(edge)
    assert_approx(actual, expected, 1e-5, "Border " .. tostring(edge))
end

-- ----------------------------------------------------------------------
-- Test cases
-- ----------------------------------------------------------------------

-- 1. Basic single node
test("single node no styles", function()
    local node = yoga.Node.create()
    node:calculateLayout(100, 100)
    assert_layout(node, 0, 0, 100, 100, "single node")
end)

test("single node with width/height", function()
    local node = yoga.Node.create()
    node:setWidth(50)
    node:setHeight(60)
    node:calculateLayout(100, 100)
    assert_layout(node, 0, 0, 50, 60, "with width/height")
end)

test("single node with margins", function()
    local node = yoga.Node.create()
    node:setWidth(50)
    node:setHeight(50)
    node:setMargin(yoga.Edge.All, 10)
    node:calculateLayout(100, 100)
    assert_layout(node, 10, 10, 50, 50, "margin all")
    assert_margin(node, yoga.Edge.Left, 10)
end)

test("single node with paddings", function()
    local node = yoga.Node.create()
    node:setWidth(100)
    node:setHeight(100)
    node:setPadding(yoga.Edge.All, 10)
    node:calculateLayout(100, 100)
    -- Node size unchanged, padding internal
    assert_layout(node, 0, 0, 100, 100, "padding all")
    assert_padding(node, yoga.Edge.Left, 10)
end)

test("single node with border", function()
    local node = yoga.Node.create()
    node:setWidth(100)
    node:setHeight(100)
    node:setBorder(yoga.Edge.All, 5)
    node:calculateLayout(100, 100)
    assert_layout(node, 0, 0, 100, 100, "border all")
    assert_border(node, yoga.Edge.Left, 5)
end)

-- 2. Flex direction row
test("flex direction row", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(30)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(30)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    assert_layout(child1, 0, 0, 30, 40, "child1 row")
    assert_layout(child2, 30, 0, 30, 40, "child2 row")
end)

test("flex direction column (default)", function()
    local parent = yoga.Node.create()
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(30)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(30)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    assert_layout(child1, 0, 0, 30, 40, "child1 column")
    assert_layout(child2, 0, 40, 30, 40, "child2 column")
end)

-- 3. Justify content
test("justify content flex-start", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setJustifyContent(yoga.Justify.FlexStart)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 0, 0, 30, 40, "flex-start")
end)

test("justify content center", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setJustifyContent(yoga.Justify.Center)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 35, 0, 30, 40, "center")
end)

test("justify content flex-end", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setJustifyContent(yoga.Justify.FlexEnd)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 70, 0, 30, 40, "flex-end")
end)

test("justify content space-between", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setJustifyContent(yoga.Justify.SpaceBetween)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(20)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(20)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    assert_layout(child1, 0, 0, 20, 40, "space-between child1")
    assert_layout(child2, 80, 0, 20, 40, "space-between child2")
end)

-- 4. Align items
test("align items stretch (row)", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setAlignItems(yoga.Align.Stretch)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    -- no height, should stretch to parent's cross axis (height)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 0, 0, 30, 100, "stretch row")
end)

test("align items center (row)", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setAlignItems(yoga.Align.Center)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 0, 30, 30, 40, "center row")
end)

test("align items flex-start (row)", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setAlignItems(yoga.Align.FlexStart)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 0, 0, 30, 40, "flex-start row")
end)

test("align items flex-end (row)", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setAlignItems(yoga.Align.FlexEnd)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    assert_layout(child, 0, 60, 30, 40, "flex-end row")
end)

-- 5. Flex grow
test("flex grow basic", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(20)
    child1:setFlexGrow(1)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(20)
    child2:setFlexGrow(1)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    -- Each gets half of remaining space: (100 - 20 - 20) / 2 = 30, plus base 20 = 50
    assert_layout(child1, 0, 0, 50, 100, "grow child1")
    assert_layout(child2, 50, 0, 50, 100, "grow child2")
end)

test("flex grow with different ratios", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(20)
    child1:setFlexGrow(1)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(20)
    child2:setFlexGrow(2)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    local totalBase = 20 + 20
    local remaining = 100 - totalBase
    local ratio = 1 + 2
    assert_layout(child1, 0, 0, 20 + remaining * 1/3, 100, "grow 1")
    assert_layout(child2, 20 + remaining * 1/3, 0, 20 + remaining * 2/3, 100, "grow 2")
end)

-- 6. Flex shrink
test("flex shrink basic", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(80)
    child1:setFlexShrink(1)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(80)
    child2:setFlexShrink(1)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    -- Total overflow = 160 - 100 = 60. Shrink each by 30.
    assert_layout(child1, 0, 0, 50, 100, "shrink child1")
    assert_layout(child2, 50, 0, 50, 100, "shrink child2")
end)

-- 7. Flex basis
test("flex basis with grow", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setFlexBasis(40)
    child:setFlexGrow(1)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    -- Basis 40, remaining 60 added, total 100
    assert_layout(child, 0, 0, 100, 100, "basis+ grow")
end)

-- 8. Gap
test("gap row", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)
    parent:setGap(yoga.Gutter.Column, 10)

    local child1 = yoga.Node.create()
    child1:setWidth(30)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(30)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    assert_layout(child1, 0, 0, 30, 40, "child1 with gap")
    assert_layout(child2, 40, 0, 30, 40, "child2 with gap") -- 30 + 10 = 40
end)

-- 9. Wrap
test("wrap row", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setFlexWrap(yoga.Wrap.Wrap)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(60)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(60)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    assert_layout(child1, 0, 0, 60, 40, "wrap child1")
    assert_layout(child2, 0, 40, 60, 40, "wrap child2") -- second line
end)

-- 10. Absolute positioning
test("absolute positioning", function()
    local parent = yoga.Node.create()
    parent:setWidth(200)
    parent:setHeight(200)
    parent:setPositionType(yoga.PositionType.Relative)

    local child = yoga.Node.create()
    child:setPositionType(yoga.PositionType.Absolute)
    child:setWidth(50)
    child:setHeight(50)
    child:setPosition(yoga.Edge.Left, 10)
    child:setPosition(yoga.Edge.Top, 20)
    parent:insertChild(child, 0)

    parent:calculateLayout(200, 200)

    assert_layout(child, 10, 20, 50, 50, "absolute positioned")
end)

test("absolute with auto margins", function()
    local parent = yoga.Node.create()
    parent:setWidth(200)
    parent:setHeight(200)
    parent:setPositionType(yoga.PositionType.Relative)

    local child = yoga.Node.create()
    child:setPositionType(yoga.PositionType.Absolute)
    child:setWidth(50)
    child:setHeight(50)
    child:setMarginAuto(yoga.Edge.Left)
    child:setMarginAuto(yoga.Edge.Right)
    parent:insertChild(child, 0)

    parent:calculateLayout(200, 200)

    -- Should be centered horizontally
    assert_approx(child:getComputedLeft(), 75, 1e-5, "absolute auto margin left")
end)

-- 11. Display none
test("display none", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local visible = yoga.Node.create()
    visible:setWidth(30)
    visible:setHeight(40)
    parent:insertChild(visible, 0)

    local hidden = yoga.Node.create()
    hidden:setWidth(30)
    hidden:setHeight(40)
    hidden:setDisplay(yoga.Display.None)
    parent:insertChild(hidden, 1)

    parent:calculateLayout(100, 100)

    assert_layout(visible, 0, 0, 30, 40, "visible child")
    assert_layout(hidden, 0, 0, 0, 0, "hidden child")
end)

-- 12. Display contents
test("display contents", function()
    local grandparent = yoga.Node.create()
    grandparent:setFlexDirection(yoga.FlexDirection.Row)
    grandparent:setWidth(100)
    grandparent:setHeight(100)

    local contents = yoga.Node.create()
    contents:setDisplay(yoga.Display.Contents)
    grandparent:insertChild(contents, 0)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    contents:insertChild(child, 0)

    grandparent:calculateLayout(100, 100)

    -- The contents node should have zero size and its child positioned directly under grandparent
    assert_layout(contents, 0, 0, 0, 0, "contents node")
    assert_layout(child, 0, 0, 30, 40, "child lifted")
end)

-- 13. Measure function
test("measure function", function()
    local node = yoga.Node.create()
    node:setMeasureFunc(function(width, widthMode, height, heightMode)
        return { width = 50, height = 60 }
    end)

    node:calculateLayout()
    assert_layout(node, 0, 0, 50, 60, "measured node")
end)

-- 14. Min/max constraints
test("min width", function()
    local node = yoga.Node.create()
    node:setWidth(20)
    node:setMinWidth(30)
    node:calculateLayout(100, 100)
    assert_layout(node, 0, 0, 30, 100, "min width")
end)

test("max width", function()
    local node = yoga.Node.create()
    node:setWidth(50)
    node:setMaxWidth(40)
    node:calculateLayout(100, 100)
    assert_layout(node, 0, 0, 40, 100, "max width")
end)

-- 15. Percentage values
test("percentage width", function()
    local parent = yoga.Node.create()
    parent:setWidth(200)
    parent:setHeight(200)

    local child = yoga.Node.create()
    child:setWidthPercent(50)
    child:setHeight(100)
    parent:insertChild(child, 0)

    parent:calculateLayout(200, 200)

    assert_layout(child, 0, 0, 100, 100, "percentage width")
end)

-- 16. Auto margins
test("auto margin on main axis", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(30)
    child:setHeight(40)
    child:setMarginAuto(yoga.Edge.Left)
    child:setMarginAuto(yoga.Edge.Right)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    -- Should be centered horizontally
    assert_approx(child:getComputedLeft(), 35, 1e-5, "auto margin main axis")
end)

-- 17. Baseline alignment
test("baseline alignment", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setAlignItems(yoga.Align.Baseline)
    parent:setWidth(200)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(50)
    child1:setHeight(40)
    child1:setMeasureFunc(function() return { width = 50, height = 40 } end) -- baseline = height
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(50)
    child2:setHeight(60)
    child2:setMeasureFunc(function() return { width = 50, height = 60 } end)
    parent:insertChild(child2, 1)

    parent:calculateLayout(200, 100)

    -- The baseline of child1 is 40, child2 is 60, so child1 should be shifted down to align baselines
    assert_approx(child1:getComputedTop(), 20, 1e-5, "baseline child1 top")
    assert_approx(child2:getComputedTop(), 0, 1e-5, "baseline child2 top")
end)

-- 18. Dirty tracking and caching
test("dirty tracking", function()
    local parent = yoga.Node.create()
    parent:setWidth(100)
    parent:setHeight(100)

    local child = yoga.Node.create()
    child:setWidth(50)
    child:setHeight(50)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)
    assert_layout(child, 0, 0, 50, 50, "initial")

    -- Change child's width
    child:setWidth(60)
    parent:calculateLayout(100, 100)
    assert_layout(child, 0, 0, 60, 50, "after change")
end)

-- 19. Overflow scroll
test("overflow scroll", function()
    local parent = yoga.Node.create()
    parent:setWidth(100)
    parent:setHeight(100)
    parent:setOverflow(yoga.Overflow.Scroll)

    local child = yoga.Node.create()
    child:setWidth(150)
    child:setHeight(150)
    parent:insertChild(child, 0)

    parent:calculateLayout(100, 100)

    -- The container should size to its content if scroll allows overflow
    assert_layout(parent, 0, 0, 100, 100, "scroll container expands to content")
end)

-- 20. Wrap reverse
test("wrap reverse", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setFlexWrap(yoga.Wrap.WrapReverse)
    parent:setWidth(100)
    parent:setHeight(100)

    local child1 = yoga.Node.create()
    child1:setWidth(60)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(60)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 100)

    -- Second line should be above first line
    assert_layout(child1, 0, 60, 60, 40, "wrap reverse child1")
    assert_layout(child2, 0, 20, 60, 40, "wrap reverse child2")
end)

-- 21. Align content
test("align content space-between", function()
    local parent = yoga.Node.create()
    parent:setFlexDirection(yoga.FlexDirection.Row)
    parent:setFlexWrap(yoga.Wrap.Wrap)
    parent:setAlignContent(yoga.Align.SpaceBetween)
    parent:setWidth(100)
    parent:setHeight(200)

    local child1 = yoga.Node.create()
    child1:setWidth(60)
    child1:setHeight(40)
    parent:insertChild(child1, 0)

    local child2 = yoga.Node.create()
    child2:setWidth(60)
    child2:setHeight(40)
    parent:insertChild(child2, 1)

    parent:calculateLayout(100, 200)

    -- Two lines, space between them
    assert_layout(child1, 0, 0, 60, 40, "child1")
    assert_layout(child2, 0, 160, 60, 40, "child2") -- 200 - 40 = 160
end)

-- ----------------------------------------------------------------------
-- Summary
-- ----------------------------------------------------------------------
print(string.format("\nTests passed: %d, failed: %d", tests_passed, tests_failed))
if tests_failed > 0 then
    os.exit(1)
else
    os.exit(0)
end