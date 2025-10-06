-- InstanceTracker.lua - WoW 1.12 (Lua 5.0) compatible

-- =======================
-- Config
-- =======================
local ADDON_NAME = "InstanceTracker"
local TRACK_DURATION = 60 * 60
local MAX_TIMERS = 5

-- ===== 5er-Instanzen: deutsch + englisch, in lowercase vergleichen =====
local DUNGEONS = {}
local function add(names)
  for i=1, table.getn(names) do DUNGEONS[string.lower(names[i])] = true end
end

add({"Ragefire Chasm","Flammenschlund"})
add({"Wailing Caverns","Die Hohlen des Wehklagens","Die Hoehlen des Wehklagens"})
add({"The Deadmines","Die Todesminen"})
add({"Shadowfang Keep","Burg Schattenfang"})
add({"Blackfathom Deeps","Tiefschwarze Grotte"})
add({"Stormwind Stockade","Das Verlies"})
add({"Gnomeregan"})
add({"Razorfen Kraul","Kral der Klingenhauer"})
add({"Scarlet Monastery","Scharlachrotes Kloster"})
add({"Razorfen Downs","Huegel der Klingenhauer"})
add({"Uldaman"})
add({"Zul'Farrak"})
add({"Maraudon"})
add({"Temple of Atal'Hakkar","Versunkener Tempel"})
add({"Blackrock Depths","Schwarzfelstiefen"})
add({"Lower Blackrock Spire","Untere Schwarzfelsspitze"})
-- add({"Upper Blackrock Spire","Obere Schwarzfelsspitze"}) -- wenn du sie tracken willst
add({"Dire Maul","Duesterbruch"})
add({"Scholomance"})
add({"Stratholme"})

-- =======================
-- SavedVariables
-- =======================
InstanceTrackerDB = InstanceTrackerDB or {
  entries = {},   -- array: { {zone=string, entered=epoch, expires=epoch}, ... }
  lastSession = 0,
}

-- =======================
-- State & Frame
-- =======================
local frame = CreateFrame("Frame") -- WoW 1.12 UI API
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- (Altlasten-Variablen, falls du sie irgendwo nutzt)
local wasInInstance = false
local lastInstanceName = nil
local lastEnterStamp = 0

-- =======================
-- Helpers (Lua 5.0 safe)
-- =======================
local function now()
  return time() -- epoch seconds (logout-fest)
end

local function tlen(t)
  return table.getn(t)
end

local function format_mmss(sec)
  if sec < 0 then sec = 0 end
  local m = math.floor(sec / 60)
  local s = math.floor(math.mod(sec, 60)) -- kein % in Lua 5.0
  return string.format("%02d:%02d", m, s)
end

local function IT_EnsureDB()
  if type(InstanceTrackerDB) ~= "table" then InstanceTrackerDB = {} end
  InstanceTrackerDB.entries = InstanceTrackerDB.entries or {}
  InstanceTrackerDB.btn     = InstanceTrackerDB.btn     or {}
  if InstanceTrackerDB.btn.shown == nil then
    InstanceTrackerDB.btn.shown = true
  end
  InstanceTrackerDB.lastSession = InstanceTrackerDB.lastSession or 0
end

local function pruneExpired()
  local t = now()
  local src = InstanceTrackerDB.entries
  local keep = {}
  local n = tlen(src)
  for i = 1, n do
    local e = src[i]
    if e and (e.expires or 0) > t then
      table.insert(keep, e)
    end
  end
  InstanceTrackerDB.entries = keep
end

local function isFiveManDungeon(zone)
  if not zone then return false end
  return DUNGEONS[string.lower(zone)] == true
end

local function canStartAnother()
  pruneExpired()
  return tlen(InstanceTrackerDB.entries) < MAX_TIMERS
end

local function addEntry(zone)
  pruneExpired()
  if not canStartAnother() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555"..ADDON_NAME.."|r: Bereits 5 IDs aktiv. Warte bis eine ablaeuft.")
    return
  end
  local t = now()
  local entry = { zone = zone or "Unknown", entered = t, expires = t + TRACK_DURATION }
  table.insert(InstanceTrackerDB.entries, entry)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Neue ID gestartet fuer |cffffff00"..entry.zone.."|r (60:00).")
end

-- =======================
-- Bestätigungs-Popup + Suppression
-- =======================
IT_CONFIRM = IT_CONFIRM or { active = false, zone = nil, stamp = 0 }
local IT_SUPPRESS = { zone = nil, untilTs = 0 } -- nach Abbruch kurz nicht erneut fragen

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["INSTANCE_TRACKER_CONFIRM"] = {
  text = "InstanceTracker:\nNeue Instanz-ID fuer \"%s\" starten?",
  button1 = "Ja",
  button2 = "Nein",

  OnAccept = function()
    if IT_CONFIRM and IT_CONFIRM.zone then
      addEntry(IT_CONFIRM.zone)
      -- Debounce erst nach Bestätigung setzen
      IT_LAST_STAMP = now()
      IT_LAST_ZONE  = IT_CONFIRM.zone
    end
    IT_CONFIRM.active = false
    IT_CONFIRM.zone = nil
  end,

  OnCancel = function()
    -- 5s Unterdrückung für die gleiche Zone
    if IT_CONFIRM and IT_CONFIRM.zone then
      IT_SUPPRESS.zone = IT_CONFIRM.zone
      IT_SUPPRESS.untilTs = now() + 5
    end
    IT_CONFIRM.active = false
    IT_CONFIRM.zone = nil
  end,

  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
  showAlert = 1,
}

-- =======================
-- Instance detection (nur via Loadscreen)
-- =======================
local IT_LAST_ZONE = nil
local IT_LAST_STAMP = 0

function tryDetectInstanceEntry(viaLoadscreen)
  local zone = GetRealZoneText()
  if not zone then return end

  -- Unterdrückung aktiv?
  if IT_SUPPRESS.zone == zone and now() < IT_SUPPRESS.untilTs then
    return
  end

  if not isFiveManDungeon(zone) then
    IT_LAST_ZONE = nil
    return
  end

  if not viaLoadscreen then
    -- Vorhof/Subzonen ignorieren
    return
  end

  local t = now()
  local isNew = (IT_LAST_ZONE ~= zone) or (t - IT_LAST_STAMP > 120)
  if not isNew then
    return
  end

  if not canStartAnother() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555"..ADDON_NAME.."|r: 5/5 IDs aktiv - kein neuer Timer.")
    return
  end

  -- Popup zeigen (nicht sofort starten)
  if not IT_CONFIRM.active then
    IT_CONFIRM.active = true
    IT_CONFIRM.zone = zone
    IT_CONFIRM.stamp = t
    StaticPopup_Show("INSTANCE_TRACKER_CONFIRM", zone)
  end
end

-- ========= Floating Button (statt Minimap) =========
-- SavedVariables: Position & Sichtbarkeit
InstanceTrackerDB = InstanceTrackerDB or {}
InstanceTrackerDB.btn = InstanceTrackerDB.btn or { shown = true }

local function IT_SaveButtonPosition(btn)
  local point, relativeTo, relativePoint, x, y = btn:GetPoint(1)
  InstanceTrackerDB.btn.point = point or "CENTER"
  InstanceTrackerDB.btn.relativePoint = relativePoint or "CENTER"
  InstanceTrackerDB.btn.x = x or 0
  InstanceTrackerDB.btn.y = y or 0
end

local function IT_RestoreButtonPosition(btn)
  local bp = InstanceTrackerDB.btn
  btn:ClearAllPoints()
  if bp and bp.point and bp.relativePoint and bp.x and bp.y then
    btn:SetPoint(bp.point, UIParent, bp.relativePoint, bp.x, bp.y)
  else
    btn:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  end
end

function InstanceTracker_RecreateFloatingButton()
  IT_EnsureDB()
  -- Clean up, falls vorhanden
  if InstanceTrackerFloatingButton then
    InstanceTrackerFloatingButton:Hide()
    InstanceTrackerFloatingButton:SetParent(nil)
    InstanceTrackerFloatingButton = nil
  end

  local btn = CreateFrame("Button", "InstanceTrackerFloatingButton", UIParent)
  btn:SetWidth(40); btn:SetHeight(40)
  btn:EnableMouse(true)
  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetFrameStrata("DIALOG")
  btn:SetFrameLevel(50)
  btn:Show()

  -- Sichtbare Optik ohne eigene Assets
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(btn)
  bg:SetTexture(0, 0, 0, 0.5)

  -- Icon (20x20, zentriert, leicht beschnitten)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  icon:SetWidth(40); icon:SetHeight(40)
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  btn.icon = icon

  -- Highlight beim Hovern
  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints(icon)
  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText("IT")

  -- Drag-Handler (1.12: 'this' statt self)
  btn:SetScript("OnDragStart", function() this:StartMoving() end)
  btn:SetScript("OnDragStop",  function() this:StopMovingOrSizing(); IT_SaveButtonPosition(this) end)

  -- Tooltip
  btn:SetScript("OnEnter", function()
    IT_EnsureDB()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("InstanceTracker", 1, 1, 1)

    pruneExpired()
    table.sort(InstanceTrackerDB.entries, function(a, b)
      return (a.expires - now()) < (b.expires - now())
    end)

    local used = table.getn(InstanceTrackerDB.entries)
    local free = MAX_TIMERS - used
    GameTooltip:AddLine(string.format("IDs benutzt: %d / %d", used, MAX_TIMERS))

    if used == 0 then
      GameTooltip:AddLine("Keine aktiven Instanz-IDs.", 0.8, 0.8, 0.8)
    else
      local t = now()
      for i = 1, used do
        local e = InstanceTrackerDB.entries[i]
        GameTooltip:AddDoubleLine(
          string.format("%d) %s", i, e.zone or "?"),
          format_mmss(e.expires - t),
          0.9, 0.9, 0.9,  1, 1, 0.2
        )
      end
    end
    if free > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format("%d weitere(r) Eintritt(e) moeglich.", free))
    end
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Click (1.12: Buttonname in 'arg1')
  btn:SetScript("OnClick", function()
    IT_EnsureDB()
    if arg1 == "RightButton" then
      local before = table.getn(InstanceTrackerDB.entries)
      pruneExpired()
      local after = table.getn(InstanceTrackerDB.entries)
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00%s|r: Aufgeraeumt (%d -> %d).", ADDON_NAME, before, after))
    else
      pruneExpired()
      if table.getn(InstanceTrackerDB.entries) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Keine aktiven IDs.")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Aktive IDs:")
        table.sort(InstanceTrackerDB.entries, function(a, b)
          return (a.expires - now()) < (b.expires - now())
        end)
        local t = now()
        for i = 1, table.getn(InstanceTrackerDB.entries) do
          local e = InstanceTrackerDB.entries[i]
          DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %d) %s - %s verbleibend",
            i, e.zone or "?", format_mmss(e.expires - t)
          ))
        end
      end
    end
  end)

  -- Position wiederherstellen
  IT_RestoreButtonPosition(btn)

  -- Sichtbarkeit anwenden
  if InstanceTrackerDB.btn.shown == false then
    btn:Hide()
  end
end

-- Alias, falls an anderer Stelle aufgerufen wird
local function createMinimapButton()
  InstanceTracker_RecreateFloatingButton()
end

-- =======================
-- Slash-Commands
-- =======================
SLASH_INSTANCETRACKER1 = "/it"
SLASH_INSTANCETRACKER2 = "/instancetracker"  -- optional

SlashCmdList["INSTANCETRACKER"] = function(msg)
  IT_EnsureDB()
  local cmd = string.lower(msg or "")

  if cmd == "clear" or cmd == "reset" then
    InstanceTrackerDB.entries = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Alle Eintraege geloescht.")

  elseif cmd == "show" or cmd == "button" then
    InstanceTrackerDB.btn.shown = true
    InstanceTracker_RecreateFloatingButton()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Floating-Button erstellt/angezeigt. Mit linker Maustaste ziehen.")

  elseif cmd == "hide" then
    InstanceTrackerDB.btn.shown = false
    if InstanceTrackerFloatingButton then InstanceTrackerFloatingButton:Hide() end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Floating-Button ausgeblendet.")

  elseif cmd == "resetbtn" then
    InstanceTrackerDB.btn = { shown = true }
    InstanceTracker_RecreateFloatingButton()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Floating-Button Position zurueckgesetzt.")

  elseif cmd == "list" or cmd == "" then
    pruneExpired()
    if tlen(InstanceTrackerDB.entries) == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Keine aktiven IDs.")
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Aktive IDs:")
    table.sort(InstanceTrackerDB.entries, function(a, b)
      return (a.expires - now()) < (b.expires - now())
    end)
    local t = now()
    for i = 1, tlen(InstanceTrackerDB.entries) do
      local e = InstanceTrackerDB.entries[i]
      DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "  %d) %s - %s verbleibend", i, e.zone or "?", format_mmss(e.expires - t)
      ))
    end

  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r Befehle: /it, /it list, /it clear, /it show, /it hide, /it resetbtn")
  end
end

-- =======================
-- Events
-- =======================
frame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
    IT_EnsureDB()
    pruneExpired()
    createMinimapButton()

  elseif event == "PLAYER_ENTERING_WORLD" then
    pruneExpired()
    tryDetectInstanceEntry(true)   -- echter Eintritt (Ladebildschirm)
    -- Verzögerte Zweitprüfung: OHNE Startflag!
    if not IT_Delayer then
      IT_Delayer = CreateFrame("Frame"); IT_Delayer:Hide(); IT_Delayer.t = 0
      IT_Delayer:SetScript("OnUpdate", function()
        IT_Delayer.t = IT_Delayer.t + arg1
        if IT_Delayer.t >= 0.5 then
          IT_Delayer:Hide()
          IT_Delayer.t = 0
          tryDetectInstanceEntry(false) -- wichtig: false, damit kein Start nach Abbruch erfolgt
        end
      end)
    end
    IT_Delayer:Show()

  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- Nur Status/Debug, nie Start
    tryDetectInstanceEntry(false)
  end
end)
