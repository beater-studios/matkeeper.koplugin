local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local PluginScreensaver = require("matkeeper/screensaver")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."

PluginScreensaver.install(PLUGIN_DIR, "matkeeper")
require("matkeeper/awake").install("matkeeper")

local OPEN_FAILED = "Matkeeper could not open. Try restarting KOReader."

-- The warning in the reader's language, from the plugin texts when they can still be read.
local function open_failed_text()
    local ok, text = pcall(function()
        local chunk = assert(loadfile(PLUGIN_DIR .. "/data/i18n.lua"))
        setfenv(chunk, {})
        local i18n = chunk()
        local code = (G_reader_settings and G_reader_settings:readSetting("language") or ""):sub(1, 2):lower()
        return (i18n[code] or i18n.en).open_failed
    end)
    return ok and type(text) == "string" and text or OPEN_FAILED
end

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
            local ok, screen = pcall(function()
                return require("matkeeper/ui/screen"):new{ plugin_dir = PLUGIN_DIR }
            end)
            if ok then
                UIManager:show(screen)
            else
                logger.warn("matkeeper: could not open", screen)
                UIManager:show(InfoMessage:new{ text = open_failed_text() })
            end
        end,
    }
end

return Matkeeper
