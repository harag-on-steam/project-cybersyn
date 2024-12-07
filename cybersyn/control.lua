--By Mami
require("scripts.constants")
require("scripts.global")
require("scripts.lib")
require("scripts.factorio-api")
require("scripts.layout")
require("scripts.central-planning")
require("scripts.train-events")
require("scripts.gui")
require("scripts.migrations")
require("scripts.migration-comb-v2")
require("scripts.main")
require("scripts.commands")
require("scripts.remote-interface")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end
