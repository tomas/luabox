-- Pure Lua port of yoga-layout (Meta's flexbox engine)
-- Matches the API surface used by Ink's layout system.
-- This is a single-pass flexbox implementation covering the subset
-- of features that Ink actually uses, plus some spec extras.

local yoga = {}

-- ----------------------------------------------------------------------
-- Enums (ported from enums.ts)
-- ----------------------------------------------------------------------
local Align = {
    Auto = 0,
    FlexStart = 1,
    Center = 2,
    FlexEnd = 3,
    Stretch = 4,
    Baseline = 5,
    SpaceBetween = 6,
    SpaceAround = 7,
    SpaceEvenly = 8,
}
yoga.Align = Align

local BoxSizing = {
    BorderBox = 0,
    ContentBox = 1,
}
yoga.BoxSizing = BoxSizing

local Dimension = {
    Width = 0,
    Height = 1,
}
yoga.Dimension = Dimension

local Direction = {
    Inherit = 0,
    LTR = 1,
    RTL = 2,
}
yoga.Direction = Direction

local Display = {
    Flex = 0,
    None = 1,
    Contents = 2,
}
yoga.Display = Display

local Edge = {
    Left = 0,
    Top = 1,
    Right = 2,
    Bottom = 3,
    Start = 4,
    End = 5,
    Horizontal = 6,
    Vertical = 7,
    All = 8,
}
yoga.Edge = Edge

local Errata = {
    None = 0,
    StretchFlexBasis = 1,
    AbsolutePositionWithoutInsetsExcludesPadding = 2,
    AbsolutePercentAgainstInnerSize = 4,
    All = 2147483647,
    Classic = 2147483646,
}
yoga.Errata = Errata

local ExperimentalFeature = {
    WebFlexBasis = 0,
}
yoga.ExperimentalFeature = ExperimentalFeature

local FlexDirection = {
    Column = 0,
    ColumnReverse = 1,
    Row = 2,
    RowReverse = 3,
}
yoga.FlexDirection = FlexDirection

local Gutter = {
    Column = 0,
    Row = 1,
    All = 2,
}
yoga.Gutter = Gutter

local Justify = {
    FlexStart = 0,
    Center = 1,
    FlexEnd = 2,
    SpaceBetween = 3,
    SpaceAround = 4,
    SpaceEvenly = 5,
}
yoga.Justify = Justify

local MeasureMode = {
    Undefined = 0,
    Exactly = 1,
    AtMost = 2,
}
yoga.MeasureMode = MeasureMode

local Overflow = {
    Visible = 0,
    Hidden = 1,
    Scroll = 2,
}
yoga.Overflow = Overflow

local PositionType = {
    Static = 0,
    Relative = 1,
    Absolute = 2,
}
yoga.PositionType = PositionType

local Unit = {
    Undefined = 0,
    Point = 1,
    Percent = 2,
    Auto = 3,
}
yoga.Unit = Unit

local Wrap = {
    NoWrap = 0,
    Wrap = 1,
    WrapReverse = 2,
}
yoga.Wrap = Wrap

-- ----------------------------------------------------------------------
-- Value types
-- ----------------------------------------------------------------------
local function pointValue(v) return { unit = Unit.Point, value = v } end
local function percentValue(v) return { unit = Unit.Percent, value = v } end

local UNDEFINED = 0/0          -- NaN
local UNDEFINED_VALUE = { unit = Unit.Undefined, value = UNDEFINED }
local AUTO_VALUE = { unit = Unit.Auto, value = UNDEFINED }

local function isDefined(n) return n == n end   -- NaN is not equal to itself
local function sameFloat(a, b)
    if a == b then return true end
    -- both NaN?
    if a ~= a and b ~= b then return true end
    return false
end

local function resolveValue(v, ownerSize)
    if v.unit == Unit.Point then
        return v.value
    elseif v.unit == Unit.Percent then
        if not isDefined(ownerSize) then return UNDEFINED end
        return v.value * ownerSize / 100
    else
        return UNDEFINED
    end
end

-- ----------------------------------------------------------------------
-- Edge resolution (9-edge → 4 physical edges)
-- ----------------------------------------------------------------------
local EDGE_LEFT = 0
local EDGE_TOP = 1
local EDGE_RIGHT = 2
local EDGE_BOTTOM = 3

local function physicalEdge(edge)
    if edge == Edge.Left or edge == Edge.Start then return EDGE_LEFT
    elseif edge == Edge.Top then return EDGE_TOP
    elseif edge == Edge.Right or edge == Edge.End then return EDGE_RIGHT
    elseif edge == Edge.Bottom then return EDGE_BOTTOM
    else return EDGE_LEFT end
end

local function resolveEdgeRaw(edges, physicalEdge)
    local v = edges[physicalEdge]
    if v.unit == Unit.Undefined then
        if physicalEdge == EDGE_LEFT or physicalEdge == EDGE_RIGHT then
            v = edges[Edge.Horizontal]
        else
            v = edges[Edge.Vertical]
        end
    end
    if v.unit == Unit.Undefined then
        v = edges[Edge.All]
    end
    if v.unit == Unit.Undefined then
        if physicalEdge == EDGE_LEFT then
            v = edges[Edge.Start]
        elseif physicalEdge == EDGE_RIGHT then
            v = edges[Edge.End]
        end
    end
    return v
end

local function resolveEdge(edges, physicalEdge, ownerSize, allowAuto)
    local v = resolveEdgeRaw(edges, physicalEdge)
    if v.unit == Unit.Auto then
        return allowAuto and UNDEFINED or 0
    end
    return resolveValue(v, ownerSize)
end

local function isMarginAuto(edges, physicalEdge)
    return resolveEdgeRaw(edges, physicalEdge).unit == Unit.Auto
end

local function hasAnyDefinedEdge(edges)
    for i = 0, 8 do
        if edges[i] and edges[i].unit ~= Unit.Undefined then
            return true
        end
    end
    return false
end

local function hasAnyAutoEdge(edges)
    for i = 0, 8 do
        if edges[i] and edges[i].unit == Unit.Auto then
            return true
        end
    end
    return false
end

local function resolveEdges4Into(edges, ownerSize, out)
    -- hoist fallbacks
    local eH = edges[Edge.Horizontal]
    local eV = edges[Edge.Vertical]
    local eA = edges[Edge.All]
    local eS = edges[Edge.Start]
    local eE = edges[Edge.End]
    local pctDenom
    if isDefined(ownerSize) then
        pctDenom = ownerSize / 100
    else
        pctDenom = UNDEFINED
    end

    -- Left
    local v = edges[0] or UNDEFINED_VALUE
    if v.unit == Unit.Undefined then v = eH end
    if v.unit == Unit.Undefined then v = eA end
    if v.unit == Unit.Undefined then v = eS end
    if v.unit == Unit.Point then
        out[0] = v.value
    elseif v.unit == Unit.Percent and isDefined(pctDenom) then
        out[0] = v.value * pctDenom
    else
        out[0] = 0
    end

    -- Top
    v = edges[1] or UNDEFINED_VALUE
    if v.unit == Unit.Undefined then v = eV end
    if v.unit == Unit.Undefined then v = eA end
    if v.unit == Unit.Point then
        out[1] = v.value
    elseif v.unit == Unit.Percent and isDefined(pctDenom) then
        out[1] = v.value * pctDenom
    else
        out[1] = 0
    end

    -- Right
    v = edges[2] or UNDEFINED_VALUE
    if v.unit == Unit.Undefined then v = eH end
    if v.unit == Unit.Undefined then v = eA end
    if v.unit == Unit.Undefined then v = eE end
    if v.unit == Unit.Point then
        out[2] = v.value
    elseif v.unit == Unit.Percent and isDefined(pctDenom) then
        out[2] = v.value * pctDenom
    else
        out[2] = 0
    end

    -- Bottom
    v = edges[3] or UNDEFINED_VALUE
    if v.unit == Unit.Undefined then v = eV end
    if v.unit == Unit.Undefined then v = eA end
    if v.unit == Unit.Point then
        out[3] = v.value
    elseif v.unit == Unit.Percent and isDefined(pctDenom) then
        out[3] = v.value * pctDenom
    else
        out[3] = 0
    end
end

-- ----------------------------------------------------------------------
-- Axis helpers
-- ----------------------------------------------------------------------
local function isRow(dir)
    return dir == FlexDirection.Row or dir == FlexDirection.RowReverse
end

local function isReverse(dir)
    return dir == FlexDirection.RowReverse or dir == FlexDirection.ColumnReverse
end

local function crossAxis(dir)
    return isRow(dir) and FlexDirection.Column or FlexDirection.Row
end

local function leadingEdge(dir)
    if dir == FlexDirection.Row then
        return EDGE_LEFT
    elseif dir == FlexDirection.RowReverse then
        return EDGE_RIGHT
    elseif dir == FlexDirection.Column then
        return EDGE_TOP
    else -- ColumnReverse
        return EDGE_BOTTOM
    end
end

local function trailingEdge(dir)
    if dir == FlexDirection.Row then
        return EDGE_RIGHT
    elseif dir == FlexDirection.RowReverse then
        return EDGE_LEFT
    elseif dir == FlexDirection.Column then
        return EDGE_BOTTOM
    else -- ColumnReverse
        return EDGE_TOP
    end
end

-- ----------------------------------------------------------------------
-- Config
-- ----------------------------------------------------------------------
local function createConfig()
    local config = {
        pointScaleFactor = 1,
        errata = Errata.None,
        useWebDefaults = false,
    }
    function config:free() end
    function config:isExperimentalFeatureEnabled(_) return false end
    function config:setExperimentalFeatureEnabled(_, _) end
    function config:setPointScaleFactor(f) self.pointScaleFactor = f end
    function config:getErrata() return self.errata end
    function config:setErrata(e) self.errata = e end
    function config:setUseWebDefaults(v) self.useWebDefaults = v end
    return config
end

local DEFAULT_CONFIG = createConfig()

-- ----------------------------------------------------------------------
-- Node implementation
-- ----------------------------------------------------------------------
local Node = {}
Node.__index = Node

local _generation = 0
local _yogaNodesVisited = 0
local _yogaMeasureCalls = 0
local _yogaCacheHits = 0
local _yogaLiveNodes = 0

function Node.new(config)
    local self = setmetatable({}, Node)
    self.style = {
        direction = Direction.Inherit,
        flexDirection = FlexDirection.Column,
        justifyContent = Justify.FlexStart,
        alignItems = Align.Stretch,
        alignSelf = Align.Auto,
        alignContent = Align.FlexStart,
        flexWrap = Wrap.NoWrap,
        overflow = Overflow.Visible,
        display = Display.Flex,
        positionType = PositionType.Relative,
        flexGrow = 0,
        flexShrink = 0,
        flexBasis = AUTO_VALUE,
        margin = {},
        padding = {},
        border = {},
        position = {},
        gap = {},
        width = AUTO_VALUE,
        height = AUTO_VALUE,
        minWidth = UNDEFINED_VALUE,
        minHeight = UNDEFINED_VALUE,
        maxWidth = UNDEFINED_VALUE,
        maxHeight = UNDEFINED_VALUE,
    }
    for i = 0, 8 do
        self.style.margin[i] = UNDEFINED_VALUE
        self.style.padding[i] = UNDEFINED_VALUE
        self.style.border[i] = UNDEFINED_VALUE
        self.style.position[i] = UNDEFINED_VALUE
    end
    for i = 0, 2 do
        self.style.gap[i] = UNDEFINED_VALUE
    end

    self.layout = {
        left = 0,
        top = 0,
        width = 0,
        height = 0,
        border = {0,0,0,0},
        padding = {0,0,0,0},
        margin = {0,0,0,0},
    }
    self.parent = nil
    self.children = {}
    self.measureFunc = nil
    self.config = config or DEFAULT_CONFIG
    self.isDirty_ = true
    self.isReferenceBaseline_ = false

    -- internal scratch
    self._flexBasis = 0
    self._mainSize = 0
    self._crossSize = 0
    self._lineIndex = 0
    self._hasAutoMargin = false
    self._hasPosition = false
    self._hasPadding = false
    self._hasBorder = false
    self._hasMargin = false

    -- cache slots
    self._lW = UNDEFINED
    self._lH = UNDEFINED
    self._lWM = 0
    self._lHM = 0
    self._lOW = UNDEFINED
    self._lOH = UNDEFINED
    self._lFW = false
    self._lFH = false
    self._lOutW = UNDEFINED
    self._lOutH = UNDEFINED
    self._hasL = false
    self._mW = UNDEFINED
    self._mH = UNDEFINED
    self._mWM = 0
    self._mHM = 0
    self._mOW = UNDEFINED
    self._mOH = UNDEFINED
    self._mOutW = UNDEFINED
    self._mOutH = UNDEFINED
    self._hasM = false

    -- flex basis cache
    self._fbBasis = UNDEFINED
    self._fbOwnerW = UNDEFINED
    self._fbOwnerH = UNDEFINED
    self._fbAvailMain = UNDEFINED
    self._fbAvailCross = UNDEFINED
    self._fbCrossMode = 0
    self._fbGen = -1

    -- multi-entry cache
    self._cIn = nil
    self._cOut = nil
    self._cGen = -1
    self._cN = 0
    self._cWr = 0

    _yogaLiveNodes = _yogaLiveNodes + 1
    return self
end

-- tree operations
function Node:insertChild(child, index)
    child.parent = self
    table.insert(self.children, index + 1, child)  -- Lua 1-based, so shift
    self:markDirty()
end

function Node:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            self:markDirty()
            break
        end
    end
end

function Node:getChild(index)
    return self.children[index + 1]   -- convert 0‑based to 1‑based
end

function Node:getChildCount()
    return #self.children
end

function Node:getParent()
    return self.parent
end

function Node:free()
    self.parent = nil
    self.children = {}
    self.measureFunc = nil
    self._cIn = nil
    self._cOut = nil
    _yogaLiveNodes = _yogaLiveNodes - 1
end

function Node:freeRecursive()
    for _, c in ipairs(self.children) do
        c:freeRecursive()
    end
    self:free()
end

function Node:reset()
    -- reset style to default (see constructor)
    local s = self.style
    s.direction = Direction.Inherit
    s.flexDirection = FlexDirection.Column
    s.justifyContent = Justify.FlexStart
    s.alignItems = Align.Stretch
    s.alignSelf = Align.Auto
    s.alignContent = Align.FlexStart
    s.flexWrap = Wrap.NoWrap
    s.overflow = Overflow.Visible
    s.display = Display.Flex
    s.positionType = PositionType.Relative
    s.flexGrow = 0
    s.flexShrink = 0
    s.flexBasis = AUTO_VALUE
    for i = 0, 8 do
        s.margin[i] = UNDEFINED_VALUE
        s.padding[i] = UNDEFINED_VALUE
        s.border[i] = UNDEFINED_VALUE
        s.position[i] = UNDEFINED_VALUE
    end
    for i = 0, 2 do
        s.gap[i] = UNDEFINED_VALUE
    end
    s.width = AUTO_VALUE
    s.height = AUTO_VALUE
    s.minWidth = UNDEFINED_VALUE
    s.minHeight = UNDEFINED_VALUE
    s.maxWidth = UNDEFINED_VALUE
    s.maxHeight = UNDEFINED_VALUE

    self.children = {}
    self.parent = nil
    self.measureFunc = nil
    self.isDirty_ = true
    self._hasAutoMargin = false
    self._hasPosition = false
    self._hasPadding = false
    self._hasBorder = false
    self._hasMargin = false
    self._hasL = false
    self._hasM = false
    self._cN = 0
    self._cWr = 0
    self._fbBasis = UNDEFINED
    self._cIn = nil
    self._cOut = nil
    self._cGen = -1
end

function Node:markDirty()
    if self.isDirty_ then return end
    self.isDirty_ = true
    if self.parent then
        self.parent:markDirty()
    end
end

function Node:isDirty()
    return self.isDirty_
end

function Node:hasNewLayout()
    return true
end

function Node:markLayoutSeen() end

function Node:setMeasureFunc(fn)
    self.measureFunc = fn
    self:markDirty()
end

function Node:unsetMeasureFunc()
    self.measureFunc = nil
    self:markDirty()
end

-- computed layout getters
function Node:getComputedLeft() return self.layout.left end
function Node:getComputedTop() return self.layout.top end
function Node:getComputedWidth() return self.layout.width end
function Node:getComputedHeight() return self.layout.height end
function Node:getComputedRight()
    local p = self.parent
    if p then
        return p.layout.width - self.layout.left - self.layout.width
    else
        return 0
    end
end
function Node:getComputedBottom()
    local p = self.parent
    if p then
        return p.layout.height - self.layout.top - self.layout.height
    else
        return 0
    end
end
function Node:getComputedLayout()
    return {
        left = self.layout.left,
        top = self.layout.top,
        right = self:getComputedRight(),
        bottom = self:getComputedBottom(),
        width = self.layout.width,
        height = self.layout.height,
    }
end
function Node:getComputedBorder(edge)
    return self.layout.border[physicalEdge(edge)]
end
function Node:getComputedPadding(edge)
    return self.layout.padding[physicalEdge(edge)]
end
function Node:getComputedMargin(edge)
    return self.layout.margin[physicalEdge(edge)]
end

-- style setters (dimensions)
local function parseDimension(v)
    if v == nil then return UNDEFINED_VALUE end
    if v == "auto" then return AUTO_VALUE end
    if type(v) == "number" then
        if v ~= v then return UNDEFINED_VALUE end   -- NaN
        return pointValue(v)
    end
    if type(v) == "string" then
        local pct = v:match("^(%d+%.?%d*)%%$")
        if pct then
            return percentValue(tonumber(pct))
        end
        local num = tonumber(v)
        if num then
            return pointValue(num)
        end
    end
    return UNDEFINED_VALUE
end

function Node:setWidth(v)
    self.style.width = parseDimension(v)
    self:markDirty()
end
function Node:setWidthPercent(v)
    self.style.width = percentValue(v)
    self:markDirty()
end
function Node:setWidthAuto()
    self.style.width = AUTO_VALUE
    self:markDirty()
end
function Node:setHeight(v)
    self.style.height = parseDimension(v)
    self:markDirty()
end
function Node:setHeightPercent(v)
    self.style.height = percentValue(v)
    self:markDirty()
end
function Node:setHeightAuto()
    self.style.height = AUTO_VALUE
    self:markDirty()
end
function Node:setMinWidth(v)
    self.style.minWidth = parseDimension(v)
    self:markDirty()
end
function Node:setMinWidthPercent(v)
    self.style.minWidth = percentValue(v)
    self:markDirty()
end
function Node:setMinHeight(v)
    self.style.minHeight = parseDimension(v)
    self:markDirty()
end
function Node:setMinHeightPercent(v)
    self.style.minHeight = percentValue(v)
    self:markDirty()
end
function Node:setMaxWidth(v)
    self.style.maxWidth = parseDimension(v)
    self:markDirty()
end
function Node:setMaxWidthPercent(v)
    self.style.maxWidth = percentValue(v)
    self:markDirty()
end
function Node:setMaxHeight(v)
    self.style.maxHeight = parseDimension(v)
    self:markDirty()
end
function Node:setMaxHeightPercent(v)
    self.style.maxHeight = percentValue(v)
    self:markDirty()
end

-- flex
function Node:setFlexDirection(dir)
    self.style.flexDirection = dir
    self:markDirty()
end
function Node:setFlexGrow(v)
    self.style.flexGrow = v or 0
    self:markDirty()
end
function Node:setFlexShrink(v)
    self.style.flexShrink = v or 0
    self:markDirty()
end
function Node:setFlex(v)
    if v == nil or v ~= v then
        self.style.flexGrow = 0
        self.style.flexShrink = 0
    elseif v > 0 then
        self.style.flexGrow = v
        self.style.flexShrink = 1
        self.style.flexBasis = pointValue(0)
    elseif v < 0 then
        self.style.flexGrow = 0
        self.style.flexShrink = -v
    else
        self.style.flexGrow = 0
        self.style.flexShrink = 0
    end
    self:markDirty()
end
function Node:setFlexBasis(v)
    self.style.flexBasis = parseDimension(v)
    self:markDirty()
end
function Node:setFlexBasisPercent(v)
    self.style.flexBasis = percentValue(v)
    self:markDirty()
end
function Node:setFlexBasisAuto()
    self.style.flexBasis = AUTO_VALUE
    self:markDirty()
end
function Node:setFlexWrap(wrap)
    self.style.flexWrap = wrap
    self:markDirty()
end

-- alignment
function Node:setAlignItems(a)
    self.style.alignItems = a
    self:markDirty()
end
function Node:setAlignSelf(a)
    self.style.alignSelf = a
    self:markDirty()
end
function Node:setAlignContent(a)
    self.style.alignContent = a
    self:markDirty()
end
function Node:setJustifyContent(j)
    self.style.justifyContent = j
    self:markDirty()
end

-- display/position/overflow
function Node:setDisplay(d)
    self.style.display = d
    self:markDirty()
end
function Node:getDisplay() return self.style.display end
function Node:setPositionType(t)
    self.style.positionType = t
    self:markDirty()
end
function Node:setPosition(edge, v)
    self.style.position[edge] = parseDimension(v)
    self._hasPosition = hasAnyDefinedEdge(self.style.position)
    self:markDirty()
end
function Node:setPositionPercent(edge, v)
    self.style.position[edge] = percentValue(v)
    self._hasPosition = true
    self:markDirty()
end
function Node:setPositionAuto(edge)
    self.style.position[edge] = AUTO_VALUE
    self._hasPosition = true
    self:markDirty()
end
function Node:setOverflow(o)
    self.style.overflow = o
    self:markDirty()
end
function Node:setDirection(d)
    self.style.direction = d
    self:markDirty()
end
function Node:setBoxSizing(_) end

-- spacing
function Node:setMargin(edge, v)
    local val = parseDimension(v)
    self.style.margin[edge] = val
    if val.unit == Unit.Auto then
        self._hasAutoMargin = true
    else
        self._hasAutoMargin = hasAnyAutoEdge(self.style.margin)
    end
    self._hasMargin = self._hasAutoMargin or hasAnyDefinedEdge(self.style.margin)
    self:markDirty()
end
function Node:setMarginPercent(edge, v)
    self.style.margin[edge] = percentValue(v)
    self._hasAutoMargin = hasAnyAutoEdge(self.style.margin)
    self._hasMargin = true
    self:markDirty()
end
function Node:setMarginAuto(edge)
    self.style.margin[edge] = AUTO_VALUE
    self._hasAutoMargin = true
    self._hasMargin = true
    self:markDirty()
end
function Node:setPadding(edge, v)
    self.style.padding[edge] = parseDimension(v)
    self._hasPadding = hasAnyDefinedEdge(self.style.padding)
    self:markDirty()
end
function Node:setPaddingPercent(edge, v)
    self.style.padding[edge] = percentValue(v)
    self._hasPadding = true
    self:markDirty()
end
function Node:setBorder(edge, v)
    self.style.border[edge] = (v == nil) and UNDEFINED_VALUE or pointValue(v)
    self._hasBorder = hasAnyDefinedEdge(self.style.border)
    self:markDirty()
end
function Node:setGap(gutter, v)
    self.style.gap[gutter] = parseDimension(v)
    self:markDirty()
end
function Node:setGapPercent(gutter, v)
    self.style.gap[gutter] = percentValue(v)
    self:markDirty()
end

-- getters (partial)
function Node:getFlexDirection() return self.style.flexDirection end
function Node:getJustifyContent() return self.style.justifyContent end
function Node:getAlignItems() return self.style.alignItems end
function Node:getAlignSelf() return self.style.alignSelf end
function Node:getAlignContent() return self.style.alignContent end
function Node:getFlexGrow() return self.style.flexGrow end
function Node:getFlexShrink() return self.style.flexShrink end
function Node:getFlexBasis() return self.style.flexBasis end
function Node:getFlexWrap() return self.style.flexWrap end
function Node:getWidth() return self.style.width end
function Node:getHeight() return self.style.height end
function Node:getOverflow() return self.style.overflow end
function Node:getPositionType() return self.style.positionType end
function Node:getDirection() return self.style.direction end

-- stubs
function Node:copyStyle(_) end
function Node:setDirtiedFunc(_) end
function Node:unsetDirtiedFunc() end
function Node:setIsReferenceBaseline(v)
    self.isReferenceBaseline_ = v
    self:markDirty()
end
function Node:isReferenceBaseline() return self.isReferenceBaseline_ end
function Node:setAspectRatio(_) end
function Node:getAspectRatio() return UNDEFINED end
function Node:setAlwaysFormsContainingBlock(_) end

-- ----------------------------------------------------------------------
-- Cache helpers
-- ----------------------------------------------------------------------
local CACHE_SLOTS = 4

local function cacheWrite(node, aW, aH, wM, hM, oW, oH, fW, fH, wasDirty)
    if not node._cIn then
        node._cIn = {}
        node._cOut = {}
    end
    if wasDirty and node._cGen ~= _generation then
        node._cN = 0
        node._cWr = 0
    end
    local i = node._cWr % CACHE_SLOTS
    node._cWr = node._cWr + 1
    if node._cN < CACHE_SLOTS then node._cN = node._cWr end
    local idx = i * 8
    node._cIn[idx] = aW
    node._cIn[idx+1] = aH
    node._cIn[idx+2] = wM
    node._cIn[idx+3] = hM
    node._cIn[idx+4] = oW
    node._cIn[idx+5] = oH
    node._cIn[idx+6] = fW and 1 or 0
    node._cIn[idx+7] = fH and 1 or 0
    node._cOut[i*2] = node.layout.width
    node._cOut[i*2+1] = node.layout.height
    node._cGen = _generation
end

local function commitCacheOutputs(node, performLayout)
    if performLayout then
        node._lOutW = node.layout.width
        node._lOutH = node.layout.height
    else
        node._mOutW = node.layout.width
        node._mOutH = node.layout.height
    end
end

-- ----------------------------------------------------------------------
-- Core layout algorithm
-- ----------------------------------------------------------------------
local function boundAxis(style, isWidth, value, ownerWidth, ownerHeight)
    local minV, maxV
    if isWidth then
        minV = style.minWidth
        maxV = style.maxWidth
    else
        minV = style.minHeight
        maxV = style.maxHeight
    end
    local minU = minV.unit
    local maxU = maxV.unit
    if minU == 0 and maxU == 0 then return value end

    local owner = isWidth and ownerWidth or ownerHeight
    local v = value
    if maxU == Unit.Point then
        if v > maxV.value then v = maxV.value end
    elseif maxU == Unit.Percent then
        local m = maxV.value * owner / 100
        if isDefined(m) and v > m then v = m end
    end
    if minU == Unit.Point then
        if v < minV.value then v = minV.value end
    elseif minU == Unit.Percent then
        local m = minV.value * owner / 100
        if isDefined(m) and v < m then v = m end
    end
    return v
end

local function resolveGap(style, gutter, ownerSize)
    local v = style.gap[gutter]
    if v.unit == Unit.Undefined then
        v = style.gap[Gutter.All]
    end
    local r = resolveValue(v, ownerSize)
    if isDefined(r) and r > 0 then return r else return 0 end
end

local function childMarginForAxis(child, axis, ownerWidth)
    if not child._hasMargin then return 0 end
    local lead = resolveEdge(child.style.margin, leadingEdge(axis), ownerWidth)
    local trail = resolveEdge(child.style.margin, trailingEdge(axis), ownerWidth)
    if isDefined(lead) and isDefined(trail) then
        return lead + trail
    else
        return 0
    end
end

local function resolveChildAlign(parent, child)
    local a = child.style.alignSelf
    if a == Align.Auto then
        return parent.style.alignItems
    else
        return a
    end
end

local function calculateBaseline(node)
    local baselineChild = nil
    for _, c in ipairs(node.children) do
        if c._lineIndex > 0 then break end
        if c.style.positionType == PositionType.Absolute then goto continue end
        if c.style.display == Display.None then goto continue end
        local childAlign = resolveChildAlign(node, c)
        if childAlign == Align.Baseline or c.isReferenceBaseline_ then
            baselineChild = c
            break
        end
        if baselineChild == nil then baselineChild = c end
        ::continue::
    end
    if baselineChild == nil then
        return node.layout.height
    end
    return calculateBaseline(baselineChild) + baselineChild.layout.top
end

local function isBaselineLayout(node, flowChildren)
    if not isRow(node.style.flexDirection) then return false end
    if node.style.alignItems == Align.Baseline then return true end
    for _, c in ipairs(flowChildren) do
        if c.style.alignSelf == Align.Baseline then return true end
    end
    return false
end

local function hasMeasureFuncInSubtree(node)
    if node.measureFunc then return true end
    for _, c in ipairs(node.children) do
        if hasMeasureFuncInSubtree(c) then return true end
    end
    return false
end

local function isStretchAlign(child)
    local p = child.parent
    if not p then return false end
    local a = child.style.alignSelf
    if a == Align.Auto then
        return p.style.alignItems == Align.Stretch
    else
        return a == Align.Stretch
    end
end

local function justifyAbsolute(justify, leadEdge, trailEdge, childSize)
    if justify == Justify.Center then
        return leadEdge + (trailEdge - leadEdge - childSize) / 2
    elseif justify == Justify.FlexEnd then
        return trailEdge - childSize
    else
        return leadEdge
    end
end

local function alignAbsolute(align, leadEdge, trailEdge, childSize, wrapReverse)
    if align == Align.Center then
        return leadEdge + (trailEdge - leadEdge - childSize) / 2
    elseif align == Align.FlexEnd then
        if wrapReverse then
            return leadEdge
        else
            return trailEdge - childSize
        end
    else
        if wrapReverse then
            return trailEdge - childSize
        else
            return leadEdge
        end
    end
end

function layoutAbsoluteChild(parent, child, parentWidth, parentHeight, pad, bor)
    local cs = child.style
    local posLeft = resolveEdgeRaw(cs.position, EDGE_LEFT)
    local posRight = resolveEdgeRaw(cs.position, EDGE_RIGHT)
    local posTop = resolveEdgeRaw(cs.position, EDGE_TOP)
    local posBottom = resolveEdgeRaw(cs.position, EDGE_BOTTOM)

    local rLeft = resolveValue(posLeft, parentWidth)
    local rRight = resolveValue(posRight, parentWidth)
    local rTop = resolveValue(posTop, parentHeight)
    local rBottom = resolveValue(posBottom, parentHeight)

    local paddingBoxW = parentWidth - bor[0] - bor[2]
    local paddingBoxH = parentHeight - bor[1] - bor[3]
    local cw = resolveValue(cs.width, paddingBoxW)
    local ch = resolveValue(cs.height, paddingBoxH)

    -- Derive width/height from left+right or top+bottom if defined
    if not isDefined(cw) and isDefined(rLeft) and isDefined(rRight) then
        cw = paddingBoxW - rLeft - rRight
    end
    if not isDefined(ch) and isDefined(rTop) and isDefined(rBottom) then
        ch = paddingBoxH - rTop - rBottom
    end

    -- Layout the absolute child (measure only, no recursion needed)
    layoutNode(child,
        cw, ch,
        isDefined(cw) and MeasureMode.Exactly or MeasureMode.Undefined,
        isDefined(ch) and MeasureMode.Exactly or MeasureMode.Undefined,
        paddingBoxW, paddingBoxH, true)

    -- Resolve margins (zero for auto, because absolute children treat auto as 0 in CSS)
    local mL = resolveEdge(cs.margin, EDGE_LEFT, parentWidth)
    local mT = resolveEdge(cs.margin, EDGE_TOP, parentWidth)
    local mR = resolveEdge(cs.margin, EDGE_RIGHT, parentWidth)
    local mB = resolveEdge(cs.margin, EDGE_BOTTOM, parentWidth)

    -- Detect auto margins (used for centering when both left/right are undefined)
    local mL_auto = resolveEdgeRaw(cs.margin, EDGE_LEFT).unit == Unit.Auto
    local mR_auto = resolveEdgeRaw(cs.margin, EDGE_RIGHT).unit == Unit.Auto
    local mT_auto = resolveEdgeRaw(cs.margin, EDGE_TOP).unit == Unit.Auto
    local mB_auto = resolveEdgeRaw(cs.margin, EDGE_BOTTOM).unit == Unit.Auto

    local mainAxis = parent.style.flexDirection
    local reversed = isReverse(mainAxis)
    local mainRow = isRow(mainAxis)
    local wrapReverse = parent.style.flexWrap == Wrap.WrapReverse
    local alignment = cs.alignSelf == Align.Auto and parent.style.alignItems or cs.alignSelf

    -- Horizontal position (left)
    local left
    if isDefined(rLeft) then
        left = bor[0] + rLeft + mL
    elseif isDefined(rRight) then
        left = parentWidth - bor[2] - rRight - child.layout.width - mR
    elseif not isDefined(rLeft) and not isDefined(rRight) then
        -- No left/right insets → use container's padding box and auto margins
        local containerWidth = parentWidth - bor[0] - bor[2]
        local used = child.layout.width
        if mL_auto and mR_auto then
            -- Center horizontally
            left = bor[0] + pad[0] + (containerWidth - used) / 2
        elseif mL_auto then
            left = bor[0] + pad[0] + (containerWidth - used - mR)
        elseif mR_auto then
            left = bor[0] + pad[0] + (containerWidth - used - mL)
        else
            -- Fallback to alignment rules (justify for main axis, align for cross)
            if mainRow then
                local lead = pad[0] + bor[0]
                local trail = parentWidth - pad[2] - bor[2]
                left = (reversed and (trail - used - mR) or justifyAbsolute(parent.style.justifyContent, lead, trail, used) + mL)
            else
                left = alignAbsolute(alignment, pad[0] + bor[0], parentWidth - pad[2] - bor[2], used, wrapReverse) + mL
            end
        end
    else
        -- Should not reach here (one side defined handled above)
        left = bor[0] + pad[0] + mL
    end

    -- Vertical position (top)
    local top
    if isDefined(rTop) then
        top = bor[1] + rTop + mT
    elseif isDefined(rBottom) then
        top = parentHeight - bor[3] - rBottom - child.layout.height - mB
    elseif not isDefined(rTop) and not isDefined(rBottom) then
        local containerHeight = parentHeight - bor[1] - bor[3]
        local used = child.layout.height
        if mT_auto and mB_auto then
            -- Center vertically
            top = bor[1] + pad[1] + (containerHeight - used) / 2
        elseif mT_auto then
            top = bor[1] + pad[1] + (containerHeight - used - mB)
        elseif mB_auto then
            top = bor[1] + pad[1] + (containerHeight - used - mT)
        else
            if mainRow then
                top = alignAbsolute(alignment, pad[1] + bor[1], parentHeight - pad[3] - bor[3], used, wrapReverse) + mT
            else
                local lead = pad[1] + bor[1]
                local trail = parentHeight - pad[3] - bor[3]
                top = (reversed and (trail - used - mB) or justifyAbsolute(parent.style.justifyContent, lead, trail, used) + mT)
            end
        end
    else
        top = bor[1] + pad[1] + mT
    end

    child.layout.left = left
    child.layout.top = top
end

local function zeroLayoutRecursive(node)
    for _, c in ipairs(node.children) do
        c.layout.left = 0
        c.layout.top = 0
        c.layout.width = 0
        c.layout.height = 0
        c.isDirty_ = true
        c._hasL = false
        c._hasM = false
        zeroLayoutRecursive(c)
    end
end

local function collectLayoutChildren(node, flow, abs)
    for _, c in ipairs(node.children) do
        local disp = c.style.display
        if disp == Display.None then
            c.layout.left = 0
            c.layout.top = 0
            c.layout.width = 0
            c.layout.height = 0
            zeroLayoutRecursive(c)
        elseif disp == Display.Contents then
            c.layout.left = 0
            c.layout.top = 0
            c.layout.width = 0
            c.layout.height = 0
            collectLayoutChildren(c, flow, abs)
        elseif c.style.positionType == PositionType.Absolute then
            table.insert(abs, c)
        else
            table.insert(flow, c)
        end
    end
end

local function computeFlexBasis(child, mainAxis, availableMain, availableCross, crossMode, ownerWidth, ownerHeight)
    local sameGen = child._fbGen == _generation
    if (sameGen or not child.isDirty_) and
        child._fbCrossMode == crossMode and
        sameFloat(child._fbOwnerW, ownerWidth) and
        sameFloat(child._fbOwnerH, ownerHeight) and
        sameFloat(child._fbAvailMain, availableMain) and
        sameFloat(child._fbAvailCross, availableCross) then
        return child._fbBasis
    end

    local cs = child.style
    local isMainRow = isRow(mainAxis)

    local basis = resolveValue(cs.flexBasis, availableMain)
    if isDefined(basis) then
        local b = math.max(0, basis)
        child._fbBasis = b
        child._fbOwnerW = ownerWidth
        child._fbOwnerH = ownerHeight
        child._fbAvailMain = availableMain
        child._fbAvailCross = availableCross
        child._fbCrossMode = crossMode
        child._fbGen = _generation
        return b
    end

    local mainStyleDim = isMainRow and cs.width or cs.height
    local mainOwner = isMainRow and ownerWidth or ownerHeight
    local resolved = resolveValue(mainStyleDim, mainOwner)
    if isDefined(resolved) then
        local b = math.max(0, resolved)
        child._fbBasis = b
        child._fbOwnerW = ownerWidth
        child._fbOwnerH = ownerHeight
        child._fbAvailMain = availableMain
        child._fbAvailCross = availableCross
        child._fbCrossMode = crossMode
        child._fbGen = _generation
        return b
    end

    local crossStyleDim = isMainRow and cs.height or cs.width
    local crossOwner = isMainRow and ownerHeight or ownerWidth
    local crossConstraint = resolveValue(crossStyleDim, crossOwner)
    local crossConstraintMode
    if isDefined(crossConstraint) then
        crossConstraintMode = MeasureMode.Exactly
    else
        crossConstraint = availableCross
        crossConstraintMode = (crossMode == MeasureMode.Exactly and isStretchAlign(child)) and MeasureMode.Exactly or MeasureMode.AtMost
    end

    local mainConstraint = UNDEFINED
    local mainConstraintMode = MeasureMode.Undefined
    if isMainRow and isDefined(availableMain) and hasMeasureFuncInSubtree(child) then
        mainConstraint = availableMain
        mainConstraintMode = MeasureMode.AtMost
    end

    local mw = isMainRow and mainConstraint or crossConstraint
    local mh = isMainRow and crossConstraint or mainConstraint
    local mwMode = isMainRow and mainConstraintMode or crossConstraintMode
    local mhMode = isMainRow and crossConstraintMode or mainConstraintMode

    layoutNode(child, mw, mh, mwMode, mhMode, ownerWidth, ownerHeight, false)

    local b = isMainRow and child.layout.width or child.layout.height
    child._fbBasis = b
    child._fbOwnerW = ownerWidth
    child._fbOwnerH = ownerHeight
    child._fbAvailMain = availableMain
    child._fbAvailCross = availableCross
    child._fbCrossMode = crossMode
    child._fbGen = _generation
    return b
end

local function resolveFlexibleLengths(children, availableInnerMain, totalFlexBasis, isMainRow, ownerW, ownerH)
    local n = #children
    local frozen = {}
    for i = 1, n do frozen[i] = false end
    local initialFree
    if isDefined(availableInnerMain) then
        initialFree = availableInnerMain - totalFlexBasis
    else
        initialFree = 0
    end

    for i = 1, n do
        local c = children[i]
        local clamped = boundAxis(c.style, isMainRow, c._flexBasis, ownerW, ownerH)
        local inflexible = not isDefined(availableInnerMain) or
            (initialFree >= 0 and c.style.flexGrow == 0) or
            (initialFree < 0 and c.style.flexShrink == 0)
        if inflexible then
            c._mainSize = math.max(0, clamped)
            frozen[i] = true
        else
            c._mainSize = c._flexBasis
        end
    end

    local unclamped = {}
    for iter = 1, n+1 do
        local frozenDelta = 0
        local totalGrow = 0
        local totalShrinkScaled = 0
        local unfrozenCount = 0
        for i = 1, n do
            local c = children[i]
            if frozen[i] then
                frozenDelta = frozenDelta + (c._mainSize - c._flexBasis)
            else
                totalGrow = totalGrow + c.style.flexGrow
                totalShrinkScaled = totalShrinkScaled + c.style.flexShrink * c._flexBasis
                unfrozenCount = unfrozenCount + 1
            end
        end
        if unfrozenCount == 0 then break end
        local remaining = initialFree - frozenDelta
        if remaining > 0 and totalGrow > 0 and totalGrow < 1 then
            local scaled = initialFree * totalGrow
            if scaled < remaining then remaining = scaled end
        elseif remaining < 0 and totalShrinkScaled > 0 then
            local totalShrink = 0
            for i = 1, n do
                if not frozen[i] then totalShrink = totalShrink + children[i].style.flexShrink end
            end
            if totalShrink < 1 then
                local scaled = initialFree * totalShrink
                if scaled > remaining then remaining = scaled end
            end
        end
        local totalViolation = 0
        for i = 1, n do
            if frozen[i] then goto continue end
            local c = children[i]
            local t = c._flexBasis
            if remaining > 0 and totalGrow > 0 then
                t = t + (remaining * c.style.flexGrow) / totalGrow
            elseif remaining < 0 and totalShrinkScaled > 0 then
                t = t + (remaining * (c.style.flexShrink * c._flexBasis)) / totalShrinkScaled
            end
            unclamped[i] = t
            local clamped = math.max(0, boundAxis(c.style, isMainRow, t, ownerW, ownerH))
            c._mainSize = clamped
            totalViolation = totalViolation + (clamped - t)
            ::continue::
        end
        if totalViolation == 0 then break end
        local anyFrozen = false
        for i = 1, n do
            if frozen[i] then goto continue2 end
            local v = children[i]._mainSize - unclamped[i]
            if (totalViolation > 0 and v > 0) or (totalViolation < 0 and v < 0) then
                frozen[i] = true
                anyFrozen = true
            end
            ::continue2::
        end
        if not anyFrozen then break end
    end
end

local function roundValue(v, scale, forceCeil, forceFloor)
    local scaled = v * scale
    local frac = scaled - math.floor(scaled)
    if frac < 0 then frac = frac + 1 end
    if frac < 0.0001 then
        scaled = math.floor(scaled)
    elseif frac > 0.9999 then
        scaled = math.ceil(scaled)
    elseif forceCeil then
        scaled = math.ceil(scaled)
    elseif forceFloor then
        scaled = math.floor(scaled)
    else
        if frac >= 0.5 then
            scaled = math.floor(scaled) + 1
        else
            scaled = math.floor(scaled)
        end
    end
    return scaled / scale
end

function roundLayout(node, scale, absLeft, absTop)
    if scale == 0 then return end
    local l = node.layout
    local nodeLeft = l.left
    local nodeTop = l.top
    local nodeWidth = l.width
    local nodeHeight = l.height

    local absNodeLeft = absLeft + nodeLeft
    local absNodeTop = absTop + nodeTop

    local isText = node.measureFunc ~= nil
    local function whole(v) return math.abs(v - math.floor(v)) < 0.0001 or math.abs(v - math.ceil(v)) < 0.0001 end
    local function roundEdge(v, forceCeil, forceFloor)
        return roundValue(v, scale, forceCeil, forceFloor)
    end

    l.left = roundEdge(nodeLeft, false, isText)
    l.top = roundEdge(nodeTop, false, isText)

    local absRight = absNodeLeft + nodeWidth
    local absBottom = absNodeTop + nodeHeight
    local hasFracW = not whole(nodeWidth * scale)
    local hasFracH = not whole(nodeHeight * scale)
    l.width = roundEdge(absRight, isText and hasFracW, isText and not hasFracW) - roundEdge(absNodeLeft, false, isText)
    l.height = roundEdge(absBottom, isText and hasFracH, isText and not hasFracH) - roundEdge(absNodeTop, false, isText)

    for _, c in ipairs(node.children) do
        roundLayout(c, scale, absNodeLeft, absNodeTop)
    end
end

-- main layoutNode function (recursive)
function layoutNode(node, availableWidth, availableHeight, widthMode, heightMode, ownerWidth, ownerHeight, performLayout, forceWidth, forceHeight)
    _yogaNodesVisited = _yogaNodesVisited + 1
    local style = node.style
    local layout = node.layout

    -- cache check
    local sameGen = node._cGen == _generation and not performLayout
    if not node.isDirty_ or sameGen then
        -- single‑slot cache
        if not node.isDirty_ and node._hasL and
            node._lWM == widthMode and node._lHM == heightMode and
            node._lFW == (forceWidth or false) and node._lFH == (forceHeight or false) and
            sameFloat(node._lW, availableWidth) and sameFloat(node._lH, availableHeight) and
            sameFloat(node._lOW, ownerWidth) and sameFloat(node._lOH, ownerHeight) then
            _yogaCacheHits = _yogaCacheHits + 1
            layout.width = node._lOutW
            layout.height = node._lOutH
            return
        end
        -- multi‑slot cache
        if node._cN > 0 and (sameGen or not node.isDirty_) then
            local cIn = node._cIn
            for i = 0, node._cN - 1 do
                local idx = i * 8
                if cIn[idx+2] == widthMode and cIn[idx+3] == heightMode and
                    cIn[idx+6] == (forceWidth and 1 or 0) and cIn[idx+7] == (forceHeight and 1 or 0) and
                    sameFloat(cIn[idx], availableWidth) and sameFloat(cIn[idx+1], availableHeight) and
                    sameFloat(cIn[idx+4], ownerWidth) and sameFloat(cIn[idx+5], ownerHeight) then
                    layout.width = node._cOut[i*2]
                    layout.height = node._cOut[i*2+1]
                    _yogaCacheHits = _yogaCacheHits + 1
                    return
                end
            end
        end
        if not node.isDirty_ and not performLayout and node._hasM and
            node._mWM == widthMode and node._mHM == heightMode and
            sameFloat(node._mW, availableWidth) and sameFloat(node._mH, availableHeight) and
            sameFloat(node._mOW, ownerWidth) and sameFloat(node._mOH, ownerHeight) then
            layout.width = node._mOutW
            layout.height = node._mOutH
            _yogaCacheHits = _yogaCacheHits + 1
            return
        end
    end

    local wasDirty = node.isDirty_
    if performLayout then
        node._lW = availableWidth
        node._lH = availableHeight
        node._lWM = widthMode
        node._lHM = heightMode
        node._lOW = ownerWidth
        node._lOH = ownerHeight
        node._lFW = forceWidth or false
        node._lFH = forceHeight or false
        node._hasL = true
        node.isDirty_ = false
        if wasDirty then node._hasM = false end
    else
        node._mW = availableWidth
        node._mH = availableHeight
        node._mWM = widthMode
        node._mHM = heightMode
        node._mOW = ownerWidth
        node._mOH = ownerHeight
        node._hasM = true
        if wasDirty then node._hasL = false end
    end

    local pad = layout.padding
    local bor = layout.border
    local mar = layout.margin
    if node._hasPadding then
        resolveEdges4Into(style.padding, ownerWidth, pad)
    else
        pad[0] = 0; pad[1] = 0; pad[2] = 0; pad[3] = 0
    end
    if node._hasBorder then
        resolveEdges4Into(style.border, ownerWidth, bor)
    else
        bor[0] = 0; bor[1] = 0; bor[2] = 0; bor[3] = 0
    end
    if node._hasMargin then
        resolveEdges4Into(style.margin, ownerWidth, mar)
    else
        mar[0] = 0; mar[1] = 0; mar[2] = 0; mar[3] = 0
    end

    local paddingBorderWidth = pad[0] + pad[2] + bor[0] + bor[2]
    local paddingBorderHeight = pad[1] + pad[3] + bor[1] + bor[3]

    local styleWidth = (forceWidth or false) and UNDEFINED or resolveValue(style.width, ownerWidth)
    local styleHeight = (forceHeight or false) and UNDEFINED or resolveValue(style.height, ownerHeight)

    local width = availableWidth
    local height = availableHeight
    local wMode = widthMode
    local hMode = heightMode
    if isDefined(styleWidth) then
        width = styleWidth
        wMode = MeasureMode.Exactly
    end
    if isDefined(styleHeight) then
        height = styleHeight
        hMode = MeasureMode.Exactly
    end

    width = boundAxis(style, true, width, ownerWidth, ownerHeight)
    height = boundAxis(style, false, height, ownerWidth, ownerHeight)

    -- measure leaf
    if node.measureFunc and #node.children == 0 then
        local innerW = (wMode == MeasureMode.Undefined) and UNDEFINED or math.max(0, width - paddingBorderWidth)
        local innerH = (hMode == MeasureMode.Undefined) and UNDEFINED or math.max(0, height - paddingBorderHeight)
        _yogaMeasureCalls = _yogaMeasureCalls + 1
        local measured = node.measureFunc(innerW, wMode, innerH, hMode)
        layout.width = (wMode == MeasureMode.Exactly) and width or boundAxis(style, true, (measured.width or 0) + paddingBorderWidth, ownerWidth, ownerHeight)
        layout.height = (hMode == MeasureMode.Exactly) and height or boundAxis(style, false, (measured.height or 0) + paddingBorderHeight, ownerWidth, ownerHeight)
        commitCacheOutputs(node, performLayout)
        cacheWrite(node, availableWidth, availableHeight, widthMode, heightMode, ownerWidth, ownerHeight, forceWidth or false, forceHeight or false, wasDirty)
        return
    end

    -- empty leaf
    if #node.children == 0 then
        layout.width = (wMode == MeasureMode.Exactly) and width or boundAxis(style, true, paddingBorderWidth, ownerWidth, ownerHeight)
        layout.height = (hMode == MeasureMode.Exactly) and height or boundAxis(style, false, paddingBorderHeight, ownerWidth, ownerHeight)
        commitCacheOutputs(node, performLayout)
        cacheWrite(node, availableWidth, availableHeight, widthMode, heightMode, ownerWidth, ownerHeight, forceWidth or false, forceHeight or false, wasDirty)
        return
    end

    -- container with children
    local mainAxis = style.flexDirection
    local crossAx = crossAxis(mainAxis)
    local isMainRow = isRow(mainAxis)

    local mainSize = isMainRow and width or height
    local crossSize = isMainRow and height or width
    local mainMode = isMainRow and wMode or hMode
    local crossMode = isMainRow and hMode or wMode
    local mainPadBorder = isMainRow and paddingBorderWidth or paddingBorderHeight
    local crossPadBorder = isMainRow and paddingBorderHeight or paddingBorderWidth

    local innerMainSize = isDefined(mainSize) and math.max(0, mainSize - mainPadBorder) or UNDEFINED
    local innerCrossSize = isDefined(crossSize) and math.max(0, crossSize - crossPadBorder) or UNDEFINED

    local gapMain = resolveGap(style, isMainRow and Gutter.Column or Gutter.Row, innerMainSize)

    local flowChildren = {}
    local absChildren = {}
    collectLayoutChildren(node, flowChildren, absChildren)

    local ownerW = isDefined(width) and width or UNDEFINED
    local ownerH = isDefined(height) and height or UNDEFINED
    local isWrap = style.flexWrap ~= Wrap.NoWrap
    local gapCross = resolveGap(style, isMainRow and Gutter.Row or Gutter.Column, innerCrossSize)

    -- step 1: compute flex‑basis
    for _, c in ipairs(flowChildren) do
        c._flexBasis = computeFlexBasis(c, mainAxis, innerMainSize, innerCrossSize, crossMode, ownerW, ownerH)
    end

    -- break into lines
    local lines = {}
    if not isWrap or not isDefined(innerMainSize) or #flowChildren == 0 then
        for _, c in ipairs(flowChildren) do
            c._lineIndex = 0
        end
        lines = { flowChildren }
    else
        local lineStart = 1
        local lineLen = 0
        for i = 1, #flowChildren do
            local c = flowChildren[i]
            local hypo = boundAxis(c.style, isMainRow, c._flexBasis, ownerW, ownerH)
            local outer = math.max(0, hypo) + childMarginForAxis(c, mainAxis, ownerW)
            local withGap = (i > lineStart) and gapMain or 0
            if i > lineStart and lineLen + withGap + outer > innerMainSize then
                local line = {}
                for j = lineStart, i-1 do
                    table.insert(line, flowChildren[j])
                end
                table.insert(lines, line)
                lineStart = i
                lineLen = outer
            else
                lineLen = lineLen + withGap + outer
            end
            c._lineIndex = #lines
        end
        local lastLine = {}
        for j = lineStart, #flowChildren do
            table.insert(lastLine, flowChildren[j])
        end
        table.insert(lines, lastLine)
    end
    local lineCount = #lines
    local isBaseline = isBaselineLayout(node, flowChildren)

    local lineConsumedMain = {}
    local lineCrossSizes = {}
    local lineMaxAscent = isBaseline and {} or nil
    local maxLineMain = 0
    local totalLinesCross = 0

    for li = 1, lineCount do
        local line = lines[li]
        local lineGap = (#line > 1) and gapMain * (#line - 1) or 0
        local lineBasis = lineGap
        for _, c in ipairs(line) do
            lineBasis = lineBasis + c._flexBasis + childMarginForAxis(c, mainAxis, ownerW)
        end

        local availMain = innerMainSize
        if not isDefined(availMain) then
            local mainOwner = isMainRow and ownerWidth or ownerHeight
            local minM = resolveValue(isMainRow and style.minWidth or style.minHeight, mainOwner)
            local maxM = resolveValue(isMainRow and style.maxWidth or style.maxHeight, mainOwner)
            if isDefined(maxM) and lineBasis > maxM - mainPadBorder then
                availMain = math.max(0, maxM - mainPadBorder)
            elseif isDefined(minM) and lineBasis < minM - mainPadBorder then
                availMain = math.max(0, minM - mainPadBorder)
            end
        end

        resolveFlexibleLengths(line, availMain, lineBasis, isMainRow, ownerW, ownerH)

        -- measure cross sizes
        local lineCross = 0
        for _, c in ipairs(line) do
            local cStyle = c.style
            local childAlign = (cStyle.alignSelf == Align.Auto) and style.alignItems or cStyle.alignSelf
            local cMarginCross = childMarginForAxis(c, crossAx, ownerW)
            local childCrossSize = UNDEFINED
            local childCrossMode = MeasureMode.Undefined
            local resolvedCrossStyle = resolveValue(isMainRow and cStyle.height or cStyle.width, isMainRow and ownerH or ownerW)
            local crossLeadE = isMainRow and EDGE_TOP or EDGE_LEFT
            local crossTrailE = isMainRow and EDGE_BOTTOM or EDGE_RIGHT
            local hasCrossAutoMargin = c._hasAutoMargin and (isMarginAuto(cStyle.margin, crossLeadE) or isMarginAuto(cStyle.margin, crossTrailE))
            if isDefined(resolvedCrossStyle) then
                childCrossSize = resolvedCrossStyle
                childCrossMode = MeasureMode.Exactly
            elseif childAlign == Align.Stretch and not hasCrossAutoMargin and not isWrap and isDefined(innerCrossSize) and crossMode == MeasureMode.Exactly then
                childCrossSize = math.max(0, innerCrossSize - cMarginCross)
                childCrossMode = MeasureMode.Exactly
            elseif not isWrap and isDefined(innerCrossSize) then
                childCrossSize = math.max(0, innerCrossSize - cMarginCross)
                childCrossMode = MeasureMode.AtMost
            end
            local cw = isMainRow and c._mainSize or childCrossSize
            local ch = isMainRow and childCrossSize or c._mainSize
            layoutNode(c, cw, ch,
                isMainRow and MeasureMode.Exactly or childCrossMode,
                isMainRow and childCrossMode or MeasureMode.Exactly,
                ownerW, ownerH, performLayout,
                isMainRow, not isMainRow)
            c._crossSize = isMainRow and c.layout.height or c.layout.width
            lineCross = math.max(lineCross, c._crossSize + cMarginCross)
        end

        if isBaseline then
            local maxAscent = 0
            local maxDescent = 0
            for _, c in ipairs(line) do
                if resolveChildAlign(node, c) == Align.Baseline then
                    local mTop = resolveEdge(c.style.margin, EDGE_TOP, ownerW)
                    local mBot = resolveEdge(c.style.margin, EDGE_BOTTOM, ownerW)
                    local ascent = calculateBaseline(c) + mTop
                    local descent = c.layout.height + mTop + mBot - ascent
                    if ascent > maxAscent then maxAscent = ascent end
                    if descent > maxDescent then maxDescent = descent end
                end
            end
            lineMaxAscent[li] = maxAscent
            if maxAscent + maxDescent > lineCross then
                lineCross = maxAscent + maxDescent
            end
        end

        local mainLead = leadingEdge(mainAxis)
        local mainTrail = trailingEdge(mainAxis)
        local consumed = lineGap
        for _, c in ipairs(line) do
            local cm = c.layout.margin
            consumed = consumed + c._mainSize + cm[mainLead] + cm[mainTrail]
        end
        lineConsumedMain[li] = consumed
        lineCrossSizes[li] = lineCross
        maxLineMain = math.max(maxLineMain, consumed)
        totalLinesCross = totalLinesCross + lineCross
    end

    local totalCrossGap = (lineCount > 1) and gapCross * (lineCount - 1) or 0
    totalLinesCross = totalLinesCross + totalCrossGap

    local isScroll = style.overflow == Overflow.Scroll
    local contentMain = maxLineMain + mainPadBorder
    local finalMainSize
    if mainMode == MeasureMode.Exactly then
        finalMainSize = mainSize
    elseif mainMode == MeasureMode.AtMost and isScroll then
        finalMainSize = math.max(math.min(mainSize, contentMain), mainPadBorder)
    elseif isWrap and lineCount > 1 and mainMode == MeasureMode.AtMost then
        finalMainSize = mainSize
    else
        finalMainSize = contentMain
    end
    local contentCross = totalLinesCross + crossPadBorder
    local finalCrossSize
    if crossMode == MeasureMode.Exactly then
        finalCrossSize = crossSize
    elseif crossMode == MeasureMode.AtMost and isScroll then
        finalCrossSize = math.max(math.min(crossSize, contentCross), crossPadBorder)
    else
        finalCrossSize = contentCross
    end
    node.layout.width = boundAxis(style, true, isMainRow and finalMainSize or finalCrossSize, ownerWidth, ownerHeight)
    node.layout.height = boundAxis(style, false, isMainRow and finalCrossSize or finalMainSize, ownerWidth, ownerHeight)

    commitCacheOutputs(node, performLayout)
    cacheWrite(node, availableWidth, availableHeight, widthMode, heightMode, ownerWidth, ownerHeight, forceWidth or false, forceHeight or false, wasDirty)

    if not performLayout then return end

    -- step 5: position children
    local actualInnerMain = (isMainRow and node.layout.width or node.layout.height) - mainPadBorder
    local actualInnerCross = (isMainRow and node.layout.height or node.layout.width) - crossPadBorder
    local mainLeadEdgePhys = leadingEdge(mainAxis)
    local mainTrailEdgePhys = trailingEdge(mainAxis)
    local crossLeadEdgePhys = isMainRow and EDGE_TOP or EDGE_LEFT
    local crossTrailEdgePhys = isMainRow and EDGE_BOTTOM or EDGE_RIGHT
    local reversed = isReverse(mainAxis)
    local mainContainerSize = isMainRow and node.layout.width or node.layout.height
    local crossLead = pad[crossLeadEdgePhys] + bor[crossLeadEdgePhys]

    local lineCrossOffset = crossLead
    local betweenLines = gapCross
    local freeCross = actualInnerCross - totalLinesCross
    if lineCount == 1 and not isWrap and not isBaseline then
        lineCrossSizes[1] = actualInnerCross
    else
        local remCross = math.max(0, freeCross)
        if style.alignContent == Align.FlexStart then
            -- nothing
        elseif style.alignContent == Align.Center then
            lineCrossOffset = lineCrossOffset + freeCross / 2
        elseif style.alignContent == Align.FlexEnd then
            lineCrossOffset = lineCrossOffset + freeCross
        elseif style.alignContent == Align.Stretch then
            if lineCount > 0 and remCross > 0 then
                local add = remCross / lineCount
                for i = 1, lineCount do
                    lineCrossSizes[i] = lineCrossSizes[i] + add
                end
            end
        elseif style.alignContent == Align.SpaceBetween then
            if lineCount > 1 then
                betweenLines = betweenLines + remCross / (lineCount - 1)
            end
        elseif style.alignContent == Align.SpaceAround then
            if lineCount > 0 then
                betweenLines = betweenLines + remCross / lineCount
                lineCrossOffset = lineCrossOffset + remCross / lineCount / 2
            end
        elseif style.alignContent == Align.SpaceEvenly then
            if lineCount > 0 then
                betweenLines = betweenLines + remCross / (lineCount + 1)
                lineCrossOffset = lineCrossOffset + remCross / (lineCount + 1)
            end
        end
    end

    local wrapReverse = style.flexWrap == Wrap.WrapReverse
    local crossContainerSize = isMainRow and node.layout.height or node.layout.width
    local lineCrossPos = lineCrossOffset
    for li = 1, lineCount do
        local line = lines[li]
        local lineCross = lineCrossSizes[li]
        local consumedMain = lineConsumedMain[li]
        local n = #line

        -- restretch if needed
        if isWrap or crossMode ~= MeasureMode.Exactly then
            for _, c in ipairs(line) do
                local cStyle = c.style
                local childAlign = (cStyle.alignSelf == Align.Auto) and style.alignItems or cStyle.alignSelf
                local crossStyleDef = isDefined(resolveValue(isMainRow and cStyle.height or cStyle.width, isMainRow and ownerH or ownerW))
                local hasCrossAutoMargin = c._hasAutoMargin and (isMarginAuto(cStyle.margin, crossLeadEdgePhys) or isMarginAuto(cStyle.margin, crossTrailEdgePhys))
                if childAlign == Align.Stretch and not crossStyleDef and not hasCrossAutoMargin then
                    local cMarginCross = childMarginForAxis(c, crossAx, ownerW)
                    local target = math.max(0, lineCross - cMarginCross)
                    if c._crossSize ~= target then
                        local cw = isMainRow and c._mainSize or target
                        local ch = isMainRow and target or c._mainSize
                        layoutNode(c, cw, ch, MeasureMode.Exactly, MeasureMode.Exactly, ownerW, ownerH, performLayout, isMainRow, not isMainRow)
                        c._crossSize = target
                    end
                end
            end
        end

        -- justify + auto margins
        local mainOffset = pad[mainLeadEdgePhys] + bor[mainLeadEdgePhys]
        local betweenMain = gapMain
        local numAutoMarginsMain = 0
        for _, c in ipairs(line) do
            if c._hasAutoMargin then
                if isMarginAuto(c.style.margin, mainLeadEdgePhys) then numAutoMarginsMain = numAutoMarginsMain + 1 end
                if isMarginAuto(c.style.margin, mainTrailEdgePhys) then numAutoMarginsMain = numAutoMarginsMain + 1 end
            end
        end
        local freeMain = actualInnerMain - consumedMain
        local remainingMain = math.max(0, freeMain)
        local autoMarginMainSize = (numAutoMarginsMain > 0 and remainingMain > 0) and remainingMain / numAutoMarginsMain or 0
        if numAutoMarginsMain == 0 then
            if style.justifyContent == Justify.FlexStart then
                -- nothing
            elseif style.justifyContent == Justify.Center then
                mainOffset = mainOffset + freeMain / 2
            elseif style.justifyContent == Justify.FlexEnd then
                mainOffset = mainOffset + freeMain
            elseif style.justifyContent == Justify.SpaceBetween then
                if n > 1 then betweenMain = betweenMain + remainingMain / (n - 1) end
            elseif style.justifyContent == Justify.SpaceAround then
                if n > 0 then
                    betweenMain = betweenMain + remainingMain / n
                    mainOffset = mainOffset + remainingMain / n / 2
                end
            elseif style.justifyContent == Justify.SpaceEvenly then
                if n > 0 then
                    betweenMain = betweenMain + remainingMain / (n + 1)
                    mainOffset = mainOffset + remainingMain / (n + 1)
                end
            end
        end

        local effectiveLineCrossPos = wrapReverse and (crossContainerSize - lineCrossPos - lineCross) or lineCrossPos

        local pos = mainOffset
        for _, c in ipairs(line) do
            local cMargin = c.style.margin
            local cLayoutMargin = c.layout.margin
            local autoMainLead = false
            local autoMainTrail = false
            local autoCrossLead = false
            local autoCrossTrail = false
            local mMainLead, mMainTrail, mCrossLead, mCrossTrail
            if c._hasAutoMargin then
                autoMainLead = isMarginAuto(cMargin, mainLeadEdgePhys)
                autoMainTrail = isMarginAuto(cMargin, mainTrailEdgePhys)
                autoCrossLead = isMarginAuto(cMargin, crossLeadEdgePhys)
                autoCrossTrail = isMarginAuto(cMargin, crossTrailEdgePhys)
                mMainLead = autoMainLead and autoMarginMainSize or cLayoutMargin[mainLeadEdgePhys]
                mMainTrail = autoMainTrail and autoMarginMainSize or cLayoutMargin[mainTrailEdgePhys]
                mCrossLead = autoCrossLead and 0 or cLayoutMargin[crossLeadEdgePhys]
                mCrossTrail = autoCrossTrail and 0 or cLayoutMargin[crossTrailEdgePhys]
            else
                mMainLead = cLayoutMargin[mainLeadEdgePhys]
                mMainTrail = cLayoutMargin[mainTrailEdgePhys]
                mCrossLead = cLayoutMargin[crossLeadEdgePhys]
                mCrossTrail = cLayoutMargin[crossTrailEdgePhys]
            end

            local mainPos = reversed and (mainContainerSize - (pos + mMainLead) - c._mainSize) or (pos + mMainLead)

            local childAlign = (c.style.alignSelf == Align.Auto) and style.alignItems or c.style.alignSelf
            local crossPos = effectiveLineCrossPos + mCrossLead
            local crossFree = lineCross - c._crossSize - mCrossLead - mCrossTrail
            if autoCrossLead and autoCrossTrail then
                crossPos = crossPos + math.max(0, crossFree) / 2
            elseif autoCrossLead then
                crossPos = crossPos + math.max(0, crossFree)
            elseif autoCrossTrail then
                -- stay
            else
                if childAlign == Align.FlexStart or childAlign == Align.Stretch then
                    if wrapReverse then crossPos = crossPos + crossFree end
                elseif childAlign == Align.Center then
                    crossPos = crossPos + crossFree / 2
                elseif childAlign == Align.FlexEnd then
                    if not wrapReverse then crossPos = crossPos + crossFree end
                elseif childAlign == Align.Baseline and isBaseline then
                    crossPos = effectiveLineCrossPos + lineMaxAscent[li] - calculateBaseline(c)
                end
            end

            local relX = 0
            local relY = 0
            if c._hasPosition then
                local relLeft = resolveValue(resolveEdgeRaw(c.style.position, EDGE_LEFT), ownerW)
                local relRight = resolveValue(resolveEdgeRaw(c.style.position, EDGE_RIGHT), ownerW)
                local relTop = resolveValue(resolveEdgeRaw(c.style.position, EDGE_TOP), ownerW)
                local relBottom = resolveValue(resolveEdgeRaw(c.style.position, EDGE_BOTTOM), ownerW)
                relX = isDefined(relLeft) and relLeft or (isDefined(relRight) and -relRight or 0)
                relY = isDefined(relTop) and relTop or (isDefined(relBottom) and -relBottom or 0)
            end

            if isMainRow then
                c.layout.left = mainPos + relX
                c.layout.top = crossPos + relY
            else
                c.layout.left = crossPos + relX
                c.layout.top = mainPos + relY
            end
            pos = pos + c._mainSize + mMainLead + mMainTrail + betweenMain
        end
        lineCrossPos = lineCrossPos + lineCross + betweenLines
    end

    -- absolute children
    for _, c in ipairs(absChildren) do
        layoutAbsoluteChild(node, c, node.layout.width, node.layout.height, pad, bor)
    end
end

-- ----------------------------------------------------------------------
-- Public API: Node and Config constructors
-- ----------------------------------------------------------------------

function Node:calculateLayout(ownerWidth, ownerHeight, _direction)
    _yogaNodesVisited = 0
    _yogaMeasureCalls = 0
    _yogaCacheHits = 0
    _generation = _generation + 1
    local w = ownerWidth == nil and UNDEFINED or ownerWidth
    local h = ownerHeight == nil and UNDEFINED or ownerHeight
    layoutNode(self, w, h,
        isDefined(w) and MeasureMode.Exactly or MeasureMode.Undefined,
        isDefined(h) and MeasureMode.Exactly or MeasureMode.Undefined,
        w, h, true)

    local mar = self.layout.margin
    local posL = resolveValue(resolveEdgeRaw(self.style.position, EDGE_LEFT), isDefined(w) and w or 0)
    local posT = resolveValue(resolveEdgeRaw(self.style.position, EDGE_TOP), isDefined(w) and w or 0)
    self.layout.left = mar[EDGE_LEFT] + (isDefined(posL) and posL or 0)
    self.layout.top = mar[EDGE_TOP] + (isDefined(posT) and posT or 0)
    roundLayout(self, self.config.pointScaleFactor, 0, 0)
end

function yoga.getYogaCounters()
    return {
        visited = _yogaNodesVisited,
        measured = _yogaMeasureCalls,
        cacheHits = _yogaCacheHits,
        live = _yogaLiveNodes,
    }
end

-- ----------------------------------------------------------------------
-- Module exports (matching yoga-layout/load)
-- ----------------------------------------------------------------------
local YOGA_INSTANCE = {
    Config = {
        create = createConfig,
        destroy = function() end,
    },
    Node = {
        create = function(config) return Node.new(config) end,
        createDefault = function() return Node.new() end,
        createWithConfig = function(config) return Node.new(config) end,
        destroy = function() end,
    },
}

-- function yoga.loadYoga()
--     return YOGA_INSTANCE
-- end

yoga.Node = YOGA_INSTANCE.Node
yoga.Config = YOGA_INSTANCE.Config

return yoga