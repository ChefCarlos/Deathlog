--[[
Copyright 2023 Yazpad
The Deathlog AddOn is distributed under the terms of the GNU General Public License (or the Lesser GPL).
This file is part of Deathlog.

The Deathlog AddOn is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The Deathlog AddOn is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with the Deathlog AddOn. If not, see <http://www.gnu.org/licenses/>.
--]]

local save_precompute = false
local use_precomputed = true
local last_attack_source = nil
local recent_msg = nil
local general_stats = {}
local log_normal_params = {}
local skull_locs = {}
local class_data = {}
local most_deadly_units = {
	["all"] = { -- server
		["all"] = { -- map_id
			["all"] = {}, -- class_id
		},
	},
}

local most_deadly_units_normalized = {
	["all"] = { -- server
		["all"] = { -- map_id
			["all"] = {}, -- class_id
		},
	},
}

deathlog_data = {}
deathlog_settings = {}

local deathlog_minimap_button_stub = nil
local deathlog_minimap_button_info = {}
local deathlog_minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject("Deathlog", {
	type = "data source",
	text = "Deathlog",
	icon = "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull",
	OnClick = function(self, btn)
		deathlogShowMenu(deathlog_data, general_stats, log_normal_params, skull_locs)
	end,
})
local function initMinimapButton()
	deathlog_minimap_button_stub = LibStub("LibDBIcon-1.0", true)
	if deathlog_minimap_button_stub:IsRegistered("Deathlog") then
		return
	end
	deathlog_minimap_button_stub:Register("Deathlog", deathlog_minimap_button, deathlog_minimap_button_info)
end

local function loadWidgets()
	Deathlog_minilog_applySettings(true)
	Deathlog_CRTWidget_applySettings()
	Deathlog_HIWidget_applySettings()
	Deathlog_HWMWidget_applySettings()
	Deathlog_DeathAlertWidget_applySettings()
end

function Deathlog_LoadFromHardcore()
	if Hardcore_Settings and Hardcore_Settings["death_log_entries"] then
		print("Retrieving deathlog entries...")
		local c = 0
		local new_entries = 0
		if deathlog_data == nil or deathlog_data["legacy"] == nil then
			deathlog_data["legacy"] = {}
		end
		local local_deathlog_fletcher16 = deathlog_fletcher16
		for _, v in ipairs(Hardcore_Settings["death_log_entries"]) do
			c = c + 1
			local checksum = local_deathlog_fletcher16(v["name"], v["guild"], v["level"], v["source_id"])
			local converted_date = deathlogConvertStringDateUnix(v["date"])
			if converted_date then
				if deathlog_data["legacy"][checksum] == nil then
					new_entries = new_entries + 1
				end
				deathlog_data["legacy"][checksum] = {
					["class_id"] = v["class_id"],
					["guild"] = v["guild"],
					["date"] = converted_date,
					["map_pos"] = v["map_pos"],
					["source_id"] = v["source_id"],
					["name"] = v["name"],
					["race_id"] = v["race_id"],
					["level"] = v["level"],
					["map_id"] = v["map_id"],
					["instance_id"] = v["instance_id"],
					["last_words"] = v["last_words"],
				}
			else
				print("failed")
			end
		end
		print("Complete. New entries: " .. new_entries .. ". Scanned: " .. c)
	end
end

local function handleEvent(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		initMinimapButton()
		if use_precomputed then
			general_stats = precomputed_general_stats
			log_normal_params = precomputed_log_normal_params
			skull_locs = precomputed_skull_locs
			dev_precomputed_general_stats = nil
			dev_precomputed_log_normal_params = nil
			dev_precomputed_skull_locs = nil
			dev_class_data = nil
		else
			Deathlog_LoadFromHardcore()
			general_stats = deathlog_calculate_statistics(deathlog_data, nil)
			log_normal_params = deathlog_calculateLogNormalParameters(deathlog_data)
			skull_locs = deathlog_calculateSkullLocs(deathlog_data)
			class_data = deathlog_calculateClassData(deathlog_data)
			if save_precompute then
				dev_precomputed_general_stats = general_stats
				dev_precomputed_log_normal_params = log_normal_params
				dev_precomputed_skull_locs = skull_locs
				dev_class_data = class_data
			else
				dev_precomputed_general_stats = nil
				dev_precomputed_log_normal_params = nil
				dev_precomputed_skull_locs = nil
			end
		end
		most_deadly_units["all"]["all"]["all"] = deathlogGetOrdered(general_stats, { "all", "all", "all", nil })
		loadWidgets()
	end
end

local function SlashHandler(msg, editbox)
	if msg == "option" or msg == "options" then
		InterfaceOptionsFrame_Show()
		InterfaceOptionsFrame_OpenToCategory("Deathlog")
	elseif msg == "alert" then
		Deathlog_DeathAlertFakeDeath()
	else
		deathlogShowMenu(deathlog_data, general_stats, log_normal_params, skull_locs)
	end
end

SLASH_DEATHLOG1, SLASH_DEATHLOG2 = "/deathlog", "/dl"
SlashCmdList["DEATHLOG"] = SlashHandler

local deathlog_event_handler = CreateFrame("Frame", "deathlog", nil, "BackdropTemplate")
deathlog_event_handler:RegisterEvent("PLAYER_ENTERING_WORLD")

deathlog_event_handler:SetScript("OnEvent", handleEvent)

local LSM30 = LibStub("LibSharedMedia-3.0", true)
local options = {
	name = "Deathlog",
	handler = Hardcore,
	type = "group",
	args = {
		load_from_hc = {
			type = "execute",
			name = "Import deathlog from hardcore",
			desc = "Import deathlog from hardcore. This will append entries.",
			width = 1.3,
			func = function()
				Deathlog_LoadFromHardcore()
			end,
		},
		require_validation = {
			type = "toggle",
			name = "Allow guildless death logging",
			desc = "Toggle guildless death logging.  Guild-based death logging requires validation from guildmates to validate.  Guildless logging allows deaths to get logged without being validated.",
			width = 1.3,
			get = function()
				if deathlog_settings["deathless_logging"] == nil then
					deathlog_settings["deathless_logging"] = true
				end
				return deathlog_settings["deathless_logging"]
			end,
			set = function()
				deathlog_settings["deathless_logging"] = not deathlog_settings["deathless_logging"]
			end,
		},
	},
}

LibStub("AceConfig-3.0"):RegisterOptionsTable("Deathlog", options)
optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Deathlog", "Deathlog", nil)

-- Hook to DeathNotificationLib
DeathNotificationLib_HookOnNewEntry(function(_player_data, _checksum, num_peer_checks, in_guild)
	local realmName = GetRealmName()
	if deathlog_data == nil then
		deathlog_data = {}
	end
	if deathlog_data[realmName] == nil then
		deathlog_data[realmName] = {}
	end

	local function deathlog_modified_fletcher16(_player_data)
		local function deathlog_fletcher16(name, guild, level, source)
			local data = name .. (guild or "") .. level .. source
			local sum1 = 0
			local sum2 = 0
			for index = 1, #data do
				sum1 = (sum1 + string.byte(string.sub(data, index, index))) % 255
				sum2 = (sum2 + sum1) % 255
			end
			return name .. "-" .. bit.bor(bit.lshift(sum2, 8), sum1)
		end
		return deathlog_fletcher16(
			_player_data["name"],
			_player_data["guild"],
			_player_data["level"],
			_player_data["source_id"]
		)
	end

	local modified_checksum = deathlog_modified_fletcher16(_player_data)
	deathlog_data[realmName][modified_checksum] = _player_data
	deathlog_widget_minilog_createEntry(_player_data)
	Deathlog_DeathAlertPlay(_player_data)
end)

-- DeathNotificationLib_HookOnNewEntrySecure(function()
-- 	print("secure!")
-- end)
