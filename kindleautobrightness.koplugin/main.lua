-- luacheck: globals G_reader_settings

local Device = require("device")
local logger = require("logger")
local _ = require("gettext")

local SETTING = "kindleautobrightness_enabled"
local WRAPPER_STATE = "_kindle_auto_brightness_bridge_state"

local function valid_intensity(powerd, intensity)
    return type(intensity) == "number"
        and intensity == intensity
        and type(powerd.fl_min) == "number"
        and type(powerd.fl_max) == "number"
        and powerd.fl_min < powerd.fl_max
        and intensity >= powerd.fl_min
        and intensity <= powerd.fl_max
end

local function has_capability(device, name)
    local method = device and device[name]
    if type(method) ~= "function" then
        return false
    end
    local ok, value = pcall(method, device)
    return ok and value == true
end

local function get_powerd(device)
    if not device or type(device.getPowerDevice) ~= "function" then
        return nil
    end
    local ok, powerd = pcall(device.getPowerDevice, device)
    if not ok or type(powerd) ~= "table" then
        return nil
    end
    return powerd
end

local function has_usable_live_read(powerd)
    if type(powerd.frontlightIntensityHW) ~= "function" then
        return false
    end
    local ok, intensity = pcall(powerd.frontlightIntensityHW, powerd)
    return ok and valid_intensity(powerd, intensity)
end

local capability_powerd = get_powerd(Device)
if not has_capability(Device, "isKindle")
        or not has_capability(Device, "hasFrontlight")
        or not has_capability(Device, "hasLightSensor")
        or not capability_powerd
        or not has_usable_live_read(capability_powerd) then
    return { disabled = true }
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local KindleAutoBrightness = WidgetContainer:extend{
    name = "kindleautobrightness",
    settings_key = SETTING,
}

local function read_live_intensity(powerd)
    if type(powerd.frontlightIntensityHW) ~= "function" then
        return nil, "reader unavailable"
    end

    local ok, intensity = pcall(powerd.frontlightIntensityHW, powerd)
    if not ok then
        return nil, "reader error: " .. tostring(intensity)
    end
    if not valid_intensity(powerd, intensity) then
        return nil, "reader returned an invalid intensity"
    end
    return intensity
end

local function fallback_intensity(powerd, original_ok, original_result)
    if original_ok and valid_intensity(powerd, original_result) then
        return original_result
    end
    if valid_intensity(powerd, powerd.fl_intensity) then
        return powerd.fl_intensity
    end
    return 0
end

local function make_wrapper(state)
    return function(this, ...)
        local original_ok, original_result = pcall(state.original_method, this, ...)
        if not original_ok then
            logger.dbg("KindleAutoBrightness: original frontlightIntensity failed", original_result)
        end

        local live_intensity, read_error = read_live_intensity(this)
        if live_intensity == nil then
            logger.dbg("KindleAutoBrightness: live frontlight read unavailable", read_error)
            return fallback_intensity(this, original_ok, original_result)
        end

        -- A minimum/off read is a state observation, not a new remembered level.
        if live_intensity <= this.fl_min then
            this.is_fl_on = false
            return 0
        end

        this.fl_intensity = live_intensity
        this.is_fl_on = true
        return live_intensity
    end
end

function KindleAutoBrightness:_ensureWrapper()
    local current_powerd = get_powerd(self.device or Device)
    if not current_powerd then
        return false
    end

    local existing = current_powerd[WRAPPER_STATE]
    if existing and existing.wrapper and current_powerd.frontlightIntensity == existing.wrapper then
        self.powerd = current_powerd
        self.wrapper_state = existing
        return true
    end
    if existing then
        if current_powerd.frontlightIntensity == existing.original_method then
            current_powerd[WRAPPER_STATE] = nil
        else
            logger.dbg("KindleAutoBrightness: refusing to replace another frontlight wrapper")
            return false
        end
    end

    local original_method = current_powerd.frontlightIntensity
    if type(original_method) ~= "function" then
        return false
    end

    local state = {
        original_method = original_method,
        original_raw_method = rawget(current_powerd, "frontlightIntensity"),
    }
    state.wrapper = make_wrapper(state)
    current_powerd[WRAPPER_STATE] = state
    current_powerd.frontlightIntensity = state.wrapper
    self.powerd = current_powerd
    self.wrapper_state = state
    return true
end

function KindleAutoBrightness:_restoreWrapper(powerd_to_restore)
    local current_powerd = powerd_to_restore or self.powerd or get_powerd(self.device or Device)
    if not current_powerd then
        return false
    end

    local state = current_powerd[WRAPPER_STATE]
    if not state then
        self.wrapper_state = nil
        return true
    end

    if current_powerd.frontlightIntensity ~= state.wrapper then
        logger.dbg("KindleAutoBrightness: leaving a changed frontlight method untouched")
        return false
    end

    if state.original_raw_method == nil then
        current_powerd.frontlightIntensity = nil
    else
        current_powerd.frontlightIntensity = state.original_raw_method
    end
    current_powerd[WRAPPER_STATE] = nil
    self.wrapper_state = nil
    return true
end

function KindleAutoBrightness:_setEnabled(enabled)
    enabled = enabled == true
    if enabled then
        local installed = self:_ensureWrapper()
        self.enabled = installed
    else
        self:_restoreWrapper()
        self.enabled = false
    end
    G_reader_settings:saveSetting(SETTING, self.enabled)
    return self.enabled
end

function KindleAutoBrightness:init()
    self.device = Device
    local stored = G_reader_settings:readSetting(SETTING)
    if stored == nil then
        self.enabled = false
        G_reader_settings:saveSetting(SETTING, false)
    else
        self.enabled = G_reader_settings:isTrue(SETTING)
    end

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    if self.enabled then
        if not self:_ensureWrapper() then
            self.enabled = false
            G_reader_settings:saveSetting(SETTING, false)
        end
    else
        self:_restoreWrapper()
    end
end

function KindleAutoBrightness:onResume()
    if self.enabled and not self:_ensureWrapper() then
        self.enabled = false
        G_reader_settings:saveSetting(SETTING, false)
    end
end

function KindleAutoBrightness:addToMainMenu(menu_items)
    menu_items.kindleautobrightness = {
        text = _("Synchronize with Kindle Auto Brightness"),
        checked_func = function()
            return self.enabled
        end,
        check_callback_updates_menu = true,
        callback = function(touchmenu_instance)
            self:_setEnabled(not self.enabled)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }
end

return KindleAutoBrightness
