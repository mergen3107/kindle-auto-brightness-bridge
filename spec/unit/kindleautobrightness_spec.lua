describe("Kindle Auto Brightness Bridge", function()
    local koreader_root = os.getenv("KINDLE_AUTO_BRIGHTNESS_KO")
    assert.is_truthy(koreader_root, "KINDLE_AUTO_BRIGHTNESS_KO must point to KOReader")

    local function extend(base, defaults)
        local class = defaults or {}
        class.__index = class
        setmetatable(class, { __index = base })
        function class:extend(values)
            local child = values or {}
            child.__index = child
            setmetatable(child, { __index = self })
            function child:new(attributes)
                local instance = attributes or {}
                setmetatable(instance, self)
                if instance.init then
                    instance:init()
                end
                return instance
            end
            return child
        end
        function class:new(attributes)
            local instance = attributes or {}
            setmetatable(instance, self)
            if instance.init then
                instance:init()
            end
            return instance
        end
        return class
    end

    package.preload["gettext"] = function()
        return setmetatable({
            pgettext = function(_, text) return text end,
        }, {
            __call = function(_, text) return text end,
        })
    end
    package.preload["logger"] = function()
        return {
            dbg = function() end,
            err = function() end,
        }
    end
    package.preload["ui/widget/container/widgetcontainer"] = function()
        return extend(nil)
    end
    package.preload["ui/widget/eventlistener"] = function()
        return extend(nil)
    end
    package.preload["ui/event"] = function()
        return {
            new = function(_, name, arg)
                return { name = name, arg = arg }
            end,
        }
    end
    package.preload["ffi/util"] = function()
        return {
            template = function(text, value)
                return (text:gsub("%%1", tostring(value)))
            end,
        }
    end
    package.preload["device/devicelistener"] = function()
        local chunk = assert(loadfile(koreader_root .. "/frontend/device/devicelistener.lua"))
        return chunk()
    end

    _G.G_reader_settings = {
        values = {},
        reset = function(self, values) self.values = values or {} end,
        readSetting = function(self, key, default)
            local value = self.values[key]
            if value == nil then return default end
            return value
        end,
        saveSetting = function(self, key, value) self.values[key] = value end,
        isTrue = function(self, key) return self.values[key] == true end,
    }

    package.replace = function(name, module)
        package.loaded[name] = module
    end
    package.unload = function(name)
        package.loaded[name] = nil
    end

    local repo_root = os.getenv("KINDLE_AUTO_BRIGHTNESS_ROOT")
    assert.is_truthy(repo_root, "KINDLE_AUTO_BRIGHTNESS_ROOT must point to the plugin repository")
    local main_path = repo_root .. "/kindleautobrightness.koplugin/main.lua"

    local original_device
    local original_notification
    local original_uimanager
    local original_devicelistener

    local SETTING = "kindleautobrightness_enabled"
    local WRAPPER_STATE = "_kindle_auto_brightness_bridge_state"

    local function reset_settings()
        _G.G_reader_settings:reset({})
    end

    local function make_powerd(options)
        options = options or {}
        local powerd = {
            fl_min = options.fl_min or 0,
            fl_max = options.fl_max or 24,
            fl_intensity = options.fl_intensity or 10,
            hardware = options.hardware or 20,
            is_fl_on = options.is_fl_on ~= false,
        }

        powerd.frontlightIntensityHW = options.frontlightIntensityHW or function(self)
            return self.hardware
        end

        powerd.frontlightIntensity = function(self)
            if not self.is_fl_on then
                return 0
            end
            return self.fl_intensity
        end

        powerd.isFrontlightOff = function(self)
            return self.hardware <= self.fl_min
        end

        powerd.stateChanged = function() end
        powerd.updateResumeFrontlightState = function(self)
            self.resume_was_on = self.is_fl_on
        end

        powerd.setIntensityHW = function(self, intensity)
            self.hardware = intensity
            if intensity > self.fl_min then
                self.fl_intensity = intensity
                self.is_fl_on = true
            else
                self.is_fl_on = false
            end
        end

        powerd.setIntensity = function(self, intensity)
            if intensity == self:frontlightIntensity() then
                return false
            end
            if intensity < self.fl_min then
                intensity = self.fl_min
            elseif intensity > self.fl_max then
                intensity = self.fl_max
            end
            self:setIntensityHW(intensity)
            return true
        end

        powerd.turnOffFrontlight = function(self)
            if self.hardware <= self.fl_min then
                return false
            end
            self:setIntensityHW(self.fl_min)
            return true
        end

        powerd.turnOnFrontlight = function(self)
            if self.hardware > self.fl_min then
                return false
            end
            self:setIntensityHW(self.fl_intensity > self.fl_min and self.fl_intensity or self.fl_min + 1)
            return true
        end

        if options.remove_live_reader then
            powerd.frontlightIntensityHW = nil
        end
        return powerd
    end

    local function make_device(options)
        options = options or {}
        local powerd = options.powerd or make_powerd(options)
        local device = {
            powerd = powerd,
            screen = {
                getWidth = function() return 100 end,
                getHeight = function() return 200 end,
            },
            show_light_dialog_calls = 0,
        }
        function device:isKindle()
            return options.kindle ~= false
        end
        function device:hasFrontlight()
            return options.frontlight ~= false
        end
        function device:hasLightSensor()
            return options.light_sensor ~= false
        end
        function device:hasGSensor()
            return false
        end
        function device:isAlwaysFullscreen()
            return true
        end
        function device:getPowerDevice()
            return self.powerd
        end
        function device:showLightDialog()
            self.show_light_dialog_calls = self.show_light_dialog_calls + 1
            self.dialog_intensity = self.powerd:frontlightIntensity()
        end
        return device
    end

    local function load_plugin(device)
        original_device = package.loaded.device
        package.replace("device", device)
        return dofile(main_path)
    end

    local function new_plugin(options, setting)
        reset_settings()
        local device = make_device(options)
        if setting ~= nil then
            _G.G_reader_settings:saveSetting(SETTING, setting)
        end
        local menu = {}
        function menu:registerToMainMenu(plugin)
            self.plugin = plugin
        end
        local plugin_class = load_plugin(device)
        if plugin_class.disabled then
            return plugin_class, nil, menu, device, device.powerd
        end
        local plugin = plugin_class:new{ ui = { menu = menu } }
        return plugin_class, plugin, menu, device, device.powerd
    end

    local function restore_module(name, module)
        package.replace(name, module)
    end

    local function load_device_listener(device, notifications)
        original_notification = package.loaded["ui/widget/notification"]
        original_uimanager = package.loaded["ui/uimanager"]
        original_devicelistener = package.loaded["device/devicelistener"]
        package.replace("device", device)
        package.replace("ui/widget/notification", {
            notify = function(_, text)
                table.insert(notifications, text)
            end,
        })
        package.replace("ui/uimanager", {
            broadcastEvent = function() end,
        })
        package.unload("device/devicelistener")
        return require("device/devicelistener")
    end

    before_each(function()
        original_device = package.loaded.device
        original_notification = package.loaded["ui/widget/notification"]
        original_uimanager = package.loaded["ui/uimanager"]
        original_devicelistener = package.loaded["device/devicelistener"]
    end)

    after_each(function()
        restore_module("device", original_device)
        restore_module("ui/widget/notification", original_notification)
        restore_module("ui/uimanager", original_uimanager)
        restore_module("device/devicelistener", original_devicelistener)
        reset_settings()
    end)

    it("is disabled on non-Kindle, non-ALS, non-frontlit, and non-readable devices", function()
        local cases = {
            { kindle = false },
            { light_sensor = false },
            { frontlight = false },
            { remove_live_reader = true },
            { frontlightIntensityHW = function() return nil end },
            { frontlightIntensityHW = function() error("read failed") end },
            { frontlightIntensityHW = function() return 25 end },
        }
        for _, options in ipairs(cases) do
            local plugin_class = new_plugin(options)
            assert.is_true(plugin_class.disabled)
        end
    end)

    it("starts disabled and persists an explicit false default", function()
        local plugin_class, plugin, _, _, powerd = new_plugin({})
        assert.is_nil(plugin_class.disabled)
        assert.is_false(plugin.enabled)
        assert.is_false(_G.G_reader_settings:readSetting(SETTING))
        assert.is_nil(powerd[WRAPPER_STATE])
    end)

    it("toggles persistently and installs the live wrapper immediately", function()
        local _, plugin, menu, _, powerd = new_plugin({})
        local menu_items = {}
        plugin:addToMainMenu(menu_items)
        local item = menu_items.kindleautobrightness
        assert.is_false(item.checked_func())

        local updates = 0
        item.callback({ updateItems = function() updates = updates + 1 end })
        assert.is_true(plugin.enabled)
        assert.is_true(_G.G_reader_settings:isTrue(SETTING))
        assert.is_not_nil(powerd[WRAPPER_STATE])
        assert.equals(1, updates)
        assert.is_true(item.checked_func())

        item.callback({ updateItems = function() updates = updates + 1 end })
        assert.is_false(plugin.enabled)
        assert.is_false(_G.G_reader_settings:isTrue(SETTING))
        assert.is_nil(powerd[WRAPPER_STATE])
        assert.equals(2, updates)
    end)

    it("is idempotent, restores the exact raw method, and survives resume", function()
        local _, plugin, _, _, powerd = new_plugin({}, true)
        local original_method = powerd[WRAPPER_STATE].original_raw_method
        assert.is_not_nil(powerd[WRAPPER_STATE])

        local wrapped_method = powerd.frontlightIntensity
        plugin:_setEnabled(true)
        plugin:onResume()
        plugin:onResume()
        assert.equals(wrapped_method, powerd.frontlightIntensity)

        plugin:_setEnabled(false)
        assert.equals(original_method, powerd.frontlightIntensity)
        assert.equals(original_method, rawget(powerd, "frontlightIntensity"))
        assert.is_nil(powerd[WRAPPER_STATE])

        plugin:_setEnabled(false)
        assert.equals(original_method, powerd.frontlightIntensity)
    end)

    it("uses live hardware through DeviceListener increments and reports the result", function()
        local _, plugin, _, device, powerd = new_plugin({}, true)
        local notifications = {}
        local device_listener = load_device_listener(device, notifications)
        local listener = setmetatable({}, { __index = device_listener })

        powerd.fl_intensity = 10
        powerd.hardware = 20
        powerd.is_fl_on = true
        listener:onChangeFlIntensity(1, 1)
        assert.equals(21, powerd.hardware)
        assert.equals(21, powerd.fl_intensity)
        assert.equals("Frontlight intensity set to 21.", notifications[#notifications])

        powerd.fl_intensity = 10
        powerd.hardware = 20
        powerd.is_fl_on = true
        listener:onChangeFlIntensity(1, -1)
        assert.equals(19, powerd.hardware)
        assert.equals(19, powerd.fl_intensity)
    end)

    it("keeps absolute brightness setting authoritative", function()
        local _, plugin, _, device, powerd = new_plugin({}, true)
        local device_listener = load_device_listener(device, {})
        local listener = setmetatable({}, { __index = device_listener })

        listener:onSetFlIntensity(12)
        assert.equals(12, powerd.hardware)
        assert.equals(12, powerd.fl_intensity)
    end)

    it("falls back without changing the cache for nil, errors, strings, and out-of-range reads", function()
        local _, plugin, _, _, powerd = new_plugin({}, true)
        local invalid_readers = {
            function() return nil end,
            function() error("temporary read failure") end,
            function() return "20" end,
            function() return 25 end,
            function() return -1 end,
        }
        for _, reader in ipairs(invalid_readers) do
            powerd.frontlightIntensityHW = reader
            powerd.fl_intensity = 10
            powerd.is_fl_on = true
            powerd.hardware = 20
            local ok, result = pcall(function() return powerd:frontlightIntensity() end)
            assert.is_true(ok)
            assert.equals(10, result)
            assert.equals(10, powerd.fl_intensity)
            assert.is_true(powerd:setIntensity(12))
            assert.equals(12, powerd.hardware)
            powerd.hardware = 20
        end
    end)

    it("does not erase remembered brightness when hardware is at the minimum", function()
        local _, plugin, _, _, powerd = new_plugin({}, true)
        powerd.fl_intensity = 10
        powerd.hardware = powerd.fl_min
        powerd.is_fl_on = true

        assert.equals(0, powerd:frontlightIntensity())
        assert.equals(10, powerd.fl_intensity)
        assert.is_false(powerd.is_fl_on)

        powerd:turnOnFrontlight()
        assert.equals(10, powerd.hardware)
        assert.equals(10, powerd.fl_intensity)
    end)

    it("lets the existing frontlight-dialog path obtain the live value", function()
        local _, plugin, _, device, powerd = new_plugin({}, true)
        powerd.hardware = 20
        powerd.fl_intensity = 10
        local notifications = {}
        local device_listener = load_device_listener(device, notifications)
        local listener = setmetatable({}, { __index = device_listener })

        listener:onShowFlDialog()
        assert.equals(1, device.show_light_dialog_calls)
        assert.equals(20, device.dialog_intensity)
    end)

    it("does not add timers or duplicate wrappers across suspend/resume", function()
        local _, plugin, _, _, powerd = new_plugin({}, true)
        local wrapper = powerd.frontlightIntensity
        plugin:onResume()
        plugin:onResume()
        assert.equals(wrapper, powerd.frontlightIntensity)
        assert.is_nil(plugin.timer)
        assert.is_nil(plugin.timers)
    end)
end)
