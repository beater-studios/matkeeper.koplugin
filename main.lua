local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local PluginScreensaver = require("matkeeper/screensaver")
local Screen = require("matkeeper/ui/screen")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."

PluginScreensaver.install(PLUGIN_DIR, "matkeeper")

local Matkeeper = WidgetContainer:extend{
    name = "matkeeper",
    is_doc_only = false,
}

function Matkeeper:init()
    self.ui.menu:registerToMainMenu(self)
end

function Matkeeper:addToMainMenu(menu_items)
    menu_items.matkeeper = {
        text = self.fullname,
        sorting_hint = "tools",
        callback = function()
            UIManager:show(Screen:new{ plugin_dir = PLUGIN_DIR })
        end,
    }
end

return Matkeeper
