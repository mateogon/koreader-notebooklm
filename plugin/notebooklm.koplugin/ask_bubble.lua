local Blitbuffer = require("ffi/blitbuffer")
local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local AskBubble = InputContainer:extend{
    text = "NotebookLM...",
    state = "running",
    action_callback = nil,
    close_callback = nil,
    timeout = nil,
    toast = true,
}

function AskBubble:init()
    local max_width = math.floor(Screen:getWidth() * 0.58)
    self.text_widget = TextWidget:new{
        text = tostring(self.text or ""),
        face = Font:getFace("smallinfofont"),
        max_width = max_width,
    }
    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.default,
        margin = Size.margin.default,
        self.text_widget,
    }
    self[1] = CustomPositionContainer:new{
        dimen = Screen:getSize(),
        horizontal_position = 0.98,
        vertical_position = 0.06,
        widget = self.frame,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapBubble = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0,
                    y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            },
        }
    end
end

function AskBubble:_dimen()
    local frame_size = self.frame:getSize()
    local screen_size = Screen:getSize()
    return Geom:new{
        x = math.floor((screen_size.w - frame_size.w) * 0.98),
        y = math.floor((screen_size.h - frame_size.h) * 0.06),
        w = frame_size.w,
        h = frame_size.h,
    }
end

function AskBubble:_close_region()
    local dimen = self:_dimen()
    local close_width = math.min(dimen.w, math.max(Size.item.height_default or 48, 44))
    return Geom:new{
        x = dimen.x + dimen.w - close_width,
        y = dimen.y,
        w = close_width,
        h = dimen.h,
    }
end

function AskBubble:onShow()
    UIManager:setDirty(self, function()
        return "ui", self:_dimen()
    end)
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            UIManager:close(self)
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
    return true
end

function AskBubble:onCloseWidget()
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
    UIManager:setDirty(nil, function()
        return "ui", self:_dimen()
    end)
end

function AskBubble:onTapBubble(_, ges)
    if not ges or not ges.pos or ges.pos:notIntersectWith(self:_dimen()) then
        return false
    end
    if not ges.pos:notIntersectWith(self:_close_region()) then
        if self.close_callback then
            self.close_callback()
        end
        UIManager:close(self)
        return false
    end
    if self.state == "ready" and self.action_callback then
        local action_callback = self.action_callback
        UIManager:close(self)
        action_callback()
    end
    return false
end

return AskBubble
