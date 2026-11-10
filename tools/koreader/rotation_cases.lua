-- Cases of tools/koreader/check_rotation.lua for this plugin.
return {
    ["matkeeper/ui/surface"] = "base class, opened only through matkeeper/ui/screen",
    ["matkeeper/ui/screen"] = function(plugin_dir)
        return { plugin_dir = plugin_dir }
    end,
}
