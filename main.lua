-- InstanceTracker.lua - WoW 1.12 (Lua 5.0) compatible
-- Erkennung per IsInInstance(): Wechsel von nil auf 1 nach Ladebildschirm = Instanz betreten, neue ID.

-- =======================
-- Config
-- =======================
local ADDON_NAME = "InstanceTracker"
local TRACK_DURATION = 60 * 60
local MAX_TIMERS = 5
local IT_Initialized = false

-- =======================
-- SavedVariables
-- =======================
InstanceTrackerDB = InstanceTrackerDB or {
  entries = {},
  lastSession = 0,
  lastInInstance = nil,
  btn = {},
  stats = {},  -- [zonename] = Anzahl Resets (dauerhaft, SavedVariables)
}

-- =======================
-- State & Frame
-- =======================
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- =======================
-- Helpers (Lua 5.0 safe)
-- =======================
local function now()
  return time()
end

local function tlen(t)
  return table.getn(t)
end

local function format_mmss(sec)
  if sec < 0 then sec = 0 end
  local m = math.floor(sec / 60)
  local s = math.floor(math.mod(sec, 60))
  return string.format("%02d:%02d", m, s)
end

local function IT_EnsureDB()
  if type(InstanceTrackerDB) ~= "table" then InstanceTrackerDB = {} end
  InstanceTrackerDB.entries = InstanceTrackerDB.entries or {}
  InstanceTrackerDB.btn = InstanceTrackerDB.btn or {}
  if InstanceTrackerDB.btn.shown == nil then
    InstanceTrackerDB.btn.shown = true
  end
  if InstanceTrackerDB.btn.locked == nil then
    InstanceTrackerDB.btn.locked = true
  end
  if InstanceTrackerDB.btn.minimapAngle == nil then
    InstanceTrackerDB.btn.minimapAngle = 90
  end
  if InstanceTrackerDB.btn.minimapShown == nil then
    InstanceTrackerDB.btn.minimapShown = true
  end
  InstanceTrackerDB.lastSession = InstanceTrackerDB.lastSession or 0
  InstanceTrackerDB.stats = InstanceTrackerDB.stats or {}
end

local function pruneExpired()
  local t = now()
  local src = InstanceTrackerDB.entries
  local keep = {}
  local n = tlen(src)
  local i
  for i = 1, n do
    local e = src[i]
    if e and (e.expires or 0) > t then
      table.insert(keep, e)
    end
  end
  InstanceTrackerDB.entries = keep
end

local function saveCurrentInInstance()
  if IsInInstance() == 1 then
    InstanceTrackerDB.lastInInstance = 1
  else
    InstanceTrackerDB.lastInInstance = nil
  end
end

local function canStartAnother()
  pruneExpired()
  return tlen(InstanceTrackerDB.entries) < MAX_TIMERS
end

local function addEntry(zone)
  pruneExpired()
  if not canStartAnother() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555"..ADDON_NAME.."|r: Already 5 IDs active. Wait until one expires.")
    return
  end
  local t = now()
  local zoneName = zone or "Unknown"
  local entry = { zone = zoneName, entered = t, expires = t + TRACK_DURATION }
  table.insert(InstanceTrackerDB.entries, entry)
  IT_EnsureDB()
  local st = InstanceTrackerDB.stats
  st[zoneName] = (st[zoneName] or 0) + 1
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: New ID started for |cffffff00"..entry.zone.."|r (60:00).")
end

-- Entfernt Eintrag an 1-basiertem Index (1..5); zieht diese ID in der Statistik wieder ab
local function removeEntryByIndex(idx)
  pruneExpired()
  local entries = InstanceTrackerDB.entries
  local n = tlen(entries)
  if idx < 1 or idx > n then
    return false
  end
  local entry = entries[idx]
  local zone = entry and entry.zone
  if zone and zone ~= "" then
    IT_EnsureDB()
    local st = InstanceTrackerDB.stats
    st[zone] = (st[zone] or 0) - 1
    if st[zone] <= 0 then
      st[zone] = nil
    end
  end
  table.remove(entries, idx)
  return true
end

-- =======================
-- Ladebildschirm-Logik: IsInInstance() von nicht-1 auf 1 = Instanz betreten
-- =======================
local IT_LoadScreenDelayer = nil

local function onAfterLoadingScreen()
  if not IT_LoadScreenDelayer then
    IT_LoadScreenDelayer = CreateFrame("Frame")
    IT_LoadScreenDelayer.t = 0
    IT_LoadScreenDelayer:SetScript("OnUpdate", function()
      local elapsed = arg1
      this.t = this.t + elapsed
      if this.t >= 1.0 then
        this:Hide()
        this.t = 0
        local newIn = IsInInstance()
        local oldIn = this.savedOldInInstance
        if oldIn ~= 1 and newIn == 1 then
          local zoneName = GetRealZoneText() or "Unknown"
          addEntry(zoneName)
        end
        if newIn == 1 then
          InstanceTrackerDB.lastInInstance = 1
        else
          InstanceTrackerDB.lastInInstance = nil
        end
      end
    end)
  end
  IT_LoadScreenDelayer.savedOldInInstance = InstanceTrackerDB.lastInInstance
  IT_LoadScreenDelayer.t = 0
  IT_LoadScreenDelayer:Show()
end

local function onZoneChange()
  saveCurrentInInstance()
end

-- =======================
-- Floating Button + List-Frame (bleibt bei Maus auf Frame)
-- =======================
local hideListTimer = nil
local listFrame = nil
local statsFrame = nil

local function IT_RefreshListFrame()
  if not listFrame or not listFrame.lines then return end
  IT_EnsureDB()
  pruneExpired()
  local entries = InstanceTrackerDB.entries
  local t = now()
  local used = tlen(entries)
  local i
  for i = 1, MAX_TIMERS do
    local line = listFrame.lines[i]
    if line then
      local text = line.text
      local btn = line.btn
      if i <= used then
        local e = entries[i]
        text:SetText(string.format("%d) %s  |cFFFFFF00%s|r", i, e.zone or "?", format_mmss(e.expires - t)))
        text:Show()
        if btn then
          btn:Show()
          btn.entryIndex = i
        end
      else
        text:Hide()
        if btn then btn:Hide() end
      end
    end
  end
  if listFrame.header then
    listFrame.header:SetText("|cff00ff00"..ADDON_NAME.."|r IDs: "..used.." / "..MAX_TIMERS)
  end
  if listFrame.emptyLabel then
    if used == 0 then
      listFrame.emptyLabel:Show()
    else
      listFrame.emptyLabel:Hide()
    end
  end
end

local function IT_ShowListFrame(anchor)
  if not listFrame then return end
  listFrame:ClearAllPoints()
  if anchor == InstanceTrackerMinimapButton then
    listFrame:SetPoint("RIGHT", anchor, "LEFT", 4, 0)
  else
    listFrame:SetPoint("LEFT", anchor, "RIGHT", -4, 0)
  end
  listFrame:Show()
  IT_RefreshListFrame()
  if hideListTimer then
    hideListTimer:Hide()
    hideListTimer = nil
  end
end

-- Prueft, ob die Maus ueber unserem List-Frame oder dem IT-Button-Container (inkl. "Entfernen") ist
local function IT_IsMouseOverOurFrames()
  local mf = GetMouseFocus()
  if not mf then return false end
  local f = mf
  while f do
    if f == listFrame or f == InstanceTrackerFloatingButton or f == InstanceTrackerMinimapButton then
      return true
    end
    f = f:GetParent()
  end
  return false
end

local function IT_HideListFrameDelayed()
  if hideListTimer then return end
  hideListTimer = CreateFrame("Frame")
  hideListTimer:SetScript("OnUpdate", function()
    local elapsed = arg1
    hideListTimer.t = (hideListTimer.t or 0) + elapsed
    if hideListTimer.t >= 0.25 then
      hideListTimer:Hide()
      hideListTimer.t = nil
      hideListTimer = nil
      if listFrame and not IT_IsMouseOverOurFrames() then
        listFrame:Hide()
      end
    end
  end)
  hideListTimer:Show()
end

local function IT_CancelHideList()
  if hideListTimer then
    hideListTimer:Hide()
    hideListTimer.t = nil
    hideListTimer = nil
  end
end

-- =======================
-- Statistik-Fenster (Resets pro Instanz, sortiert nach Anzahl, Höhe wächst mit)
-- =======================
local STATS_MAX_LINES = 80
local STATS_LINE_HEIGHT = 14
local STATS_FRAME_WIDTH = 200
local STATS_HEADER_HEIGHT = 24
local STATS_PADDING_BOTTOM = 8

local function IT_CreateStatsFrame()
  if statsFrame then return end
  IT_EnsureDB()
  local sf = CreateFrame("Frame", "InstanceTrackerStatsFrame", UIParent)
  sf:SetFrameStrata("DIALOG")
  sf:SetFrameLevel(60)
  sf:SetWidth(STATS_FRAME_WIDTH)
  sf:SetHeight(STATS_HEADER_HEIGHT + STATS_PADDING_BOTTOM)
  sf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  sf:EnableMouse(true)
  sf:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  sf:SetBackdropColor(0, 0, 0, 0.9)
  sf:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

  local title = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", sf, "TOPLEFT", 6, -6)
  title:SetText("|cff00ff00" .. ADDON_NAME .. "|r Statistics:")

  local closeBtn = CreateFrame("Button", nil, sf)
  closeBtn:SetWidth(20)
  closeBtn:SetHeight(20)
  closeBtn:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -2)
  local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  closeTex:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
  closeTex:SetText("X")
  closeTex:SetTextColor(1, 0.3, 0.3)
  closeBtn:SetScript("OnClick", function()
    if this and this:GetParent() then
      this:GetParent():Hide()
    end
  end)
  closeBtn:SetScript("OnEnter", function()
    if closeTex then closeTex:SetTextColor(1, 0.6, 0.6) end
  end)
  closeBtn:SetScript("OnLeave", function()
    if closeTex then closeTex:SetTextColor(1, 0.3, 0.3) end
  end)

  sf.lines = {}
  local prev = title
  local i
  for i = 1, STATS_MAX_LINES do
    local line = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line:SetJustifyH("LEFT")
    if i == 1 then
      line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    else
      line:SetPoint("TOPLEFT", sf.lines[i - 1], "BOTTOMLEFT", 0, 0)
    end
    line:SetWidth(STATS_FRAME_WIDTH - 20)
    line:SetHeight(STATS_LINE_HEIGHT)
    line:SetTextColor(0.9, 0.9, 0.9)
    sf.lines[i] = line
  end
  statsFrame = sf
  sf:Hide()
end

local function IT_RefreshStatsFrame()
  if not statsFrame then return end
  IT_EnsureDB()
  local st = InstanceTrackerDB.stats
  local keys = {}
  local z
  for z in pairs(st) do
    table.insert(keys, z)
  end
  -- Nach ID-Anzahl absteigend (meiste oben)
  table.sort(keys, function(a, b) return (st[a] or 0) > (st[b] or 0) end)
  local n = table.getn(keys)
  local i, line
  for i = 1, STATS_MAX_LINES do
    line = statsFrame.lines[i]
    if line then
      if keys[i] then
        line:SetText(keys[i] .. ": " .. st[keys[i]])
        line:Show()
      else
        line:Hide()
      end
    end
  end
  -- Fensterhöhe an Anzahl Einträge anpassen (wächst nach unten)
  local contentH = n * STATS_LINE_HEIGHT
  if contentH < 0 then contentH = 0 end
  statsFrame:SetHeight(STATS_HEADER_HEIGHT + contentH + STATS_PADDING_BOTTOM)
end

function IT_ShowStatsFrame()
  IT_CreateStatsFrame()
  IT_RefreshStatsFrame()
  if statsFrame then statsFrame:Show() end
end

local MINIMAP_RADIUS = 78

local function IT_UpdateMinimapButtonPosition()
  if not InstanceTrackerMinimapButton then return end
  local angle = (InstanceTrackerDB.btn.minimapAngle or 90) * 3.14159265358979 / 180
  local x = MINIMAP_RADIUS * math.cos(angle)
  local y = MINIMAP_RADIUS * math.sin(angle)
  InstanceTrackerMinimapButton:ClearAllPoints()
  InstanceTrackerMinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function IT_CreateMinimapButton()
  if InstanceTrackerMinimapButton then
    IT_UpdateMinimapButtonPosition()
    if InstanceTrackerDB.btn.minimapShown then
      InstanceTrackerMinimapButton:Show()
    else
      InstanceTrackerMinimapButton:Hide()
    end
    return
  end
  -- Layout wie LibDBIcon-1.0 / DoiteAuras: 31x31 Button, Overlay TOPLEFT, Icon TOPLEFT mit Offsets
  local mb = CreateFrame("Button", "InstanceTrackerMinimapButton", Minimap)
  mb:SetWidth(31)
  mb:SetHeight(31)
  mb:SetFrameStrata("MEDIUM")
  mb:SetFrameLevel(8)
  mb:RegisterForDrag("LeftButton")
  mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

  local border = mb:CreateTexture(nil, "OVERLAY")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)

  local icon = mb:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetWidth(17)
  icon:SetHeight(17)
  icon:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -6)

  mb:SetScript("OnClick", function()
    if this.dragging then return end
    IT_ShowStatsFrame()
  end)
  mb:SetScript("OnEnter", function()
    if this.dragging then return end
    IT_ShowListFrame(this)
  end)
  mb:SetScript("OnLeave", function()
    IT_HideListFrameDelayed()
  end)
  mb:SetScript("OnDragStart", function()
    this.dragging = true
    if listFrame then listFrame:Hide() end
  end)
  mb:SetScript("OnDragStop", function()
    this.dragging = false
  end)
  mb:SetScript("OnUpdate", function()
    if not this.dragging then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = UIParent:GetScale()
    if scale and scale > 0 then
      px = px / scale
      py = py / scale
    end
    local dx = px - mx
    local dy = py - my
    local angle = math.atan2(dy, dx) * 180 / 3.14159265358979
    if angle < 0 then angle = angle + 360 end
    InstanceTrackerDB.btn.minimapAngle = angle
    IT_UpdateMinimapButtonPosition()
  end)

  IT_UpdateMinimapButtonPosition()
  if InstanceTrackerDB.btn.minimapShown then
    mb:Show()
  else
    mb:Hide()
  end
end

function InstanceTracker_RecreateFloatingButton()
  IT_EnsureDB()
  if InstanceTrackerFloatingButton then
    InstanceTrackerFloatingButton:Hide()
    InstanceTrackerFloatingButton:SetParent(nil)
    InstanceTrackerFloatingButton = nil
  end
  if listFrame then
    listFrame:Hide()
    listFrame:SetParent(nil)
    listFrame = nil
  end

  local container = CreateFrame("Frame", "InstanceTrackerFloatingButton", UIParent)
  container:SetWidth(40)
  container:SetHeight(40)
  container:EnableMouse(true)
  container:SetFrameStrata("DIALOG")
  container:SetFrameLevel(50)

  local btn = CreateFrame("Button", nil, container)
  btn:SetWidth(40)
  btn:SetHeight(40)
  btn:SetPoint("LEFT", container, "LEFT", 0, 0)
  btn:EnableMouse(true)
  btn:SetMovable(false)
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function()
    if InstanceTrackerDB.btn.locked then return end
    container:StartMoving()
  end)
  btn:SetScript("OnDragStop", function()
    container:StopMovingOrSizing()
    local bp = InstanceTrackerDB.btn
    local point, _, relativePoint, x, y = container:GetPoint(1)
    bp.point = point or "CENTER"
    bp.relativePoint = relativePoint or "CENTER"
    bp.x = x or 0
    bp.y = y or 0
  end)

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(btn)
  bg:SetTexture(0, 0, 0, 0.5)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  icon:SetWidth(40)
  icon:SetHeight(40)
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints(icon)

  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText("IT")

  container:SetMovable(true)

  btn:SetScript("OnEnter", function()
    IT_ShowListFrame(container)
  end)
  btn:SetScript("OnLeave", function()
    IT_HideListFrameDelayed()
  end)

  -- List-Frame (bleibt sichtbar, wenn Maus von Button auf Frame wechselt)
  listFrame = CreateFrame("Frame", nil, UIParent)
  listFrame:SetFrameStrata("DIALOG")
  listFrame:SetFrameLevel(51)
  listFrame:SetWidth(208)
  listFrame:SetHeight(120)
  listFrame:EnableMouse(true)
  listFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  listFrame:SetBackdropColor(0, 0, 0, 0.85)
  listFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

  listFrame:SetScript("OnEnter", function()
    IT_CancelHideList()
  end)
  listFrame:SetScript("OnLeave", function()
    IT_HideListFrameDelayed()
  end)

  local header = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 8, -8)
  header:SetText("|cff00ff00"..ADDON_NAME.."|r IDs: 0 / " .. MAX_TIMERS)
  listFrame.header = header

  local emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  emptyLabel:SetPoint("CENTER", listFrame, "CENTER", 0, 0)
  emptyLabel:SetText("No active dungeon IDs")
  emptyLabel:SetTextColor(0.7, 0.7, 0.7)
  listFrame.emptyLabel = emptyLabel

  listFrame.lines = {}
  local prev
  local rowWidth = 202
  for i = 1, MAX_TIMERS do
    local row = CreateFrame("Frame", nil, listFrame)
    row:SetWidth(rowWidth)
    row:SetHeight(18)
    if i == 1 then
      row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    else
      row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
    end
    prev = row

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", row, "LEFT", 0, 0)
    text:SetWidth(rowWidth - 70)
    text:SetJustifyH("LEFT")
    text:SetTextColor(0.9, 0.9, 0.9)

    local remBtn = CreateFrame("Button", nil, row)
    remBtn:SetWidth(60)
    remBtn:SetHeight(16)
    remBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local btnLabel = remBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnLabel:SetPoint("CENTER", remBtn, "CENTER", 0, 0)
    btnLabel:SetText("Remove")
    btnLabel:SetTextColor(1, 0.4, 0.4)
    remBtn.entryIndex = i
    remBtn:SetScript("OnClick", function()
      local idx = this.entryIndex
      if removeEntryByIndex(idx) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: ID "..idx.." removed.")
        IT_RefreshListFrame()
      end
    end)
    listFrame.lines[i] = { text = text, btn = remBtn }
  end

  listFrame:Hide()

  -- Button-Klick (links/rechts)
  btn:SetScript("OnClick", function()
    IT_EnsureDB()
    local a1 = arg1
    if a1 == "RightButton" then
      local before = tlen(InstanceTrackerDB.entries)
      pruneExpired()
      local after = tlen(InstanceTrackerDB.entries)
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00%s|r: Cleaned up (%d -> %d).", ADDON_NAME, before, after))
      IT_RefreshListFrame()
    else
      pruneExpired()
      if tlen(InstanceTrackerDB.entries) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: No active IDs.")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Active IDs:")
        table.sort(InstanceTrackerDB.entries, function(a, b)
          return (a.expires - now()) < (b.expires - now())
        end)
        local t = now()
        local i
        for i = 1, tlen(InstanceTrackerDB.entries) do
          local e = InstanceTrackerDB.entries[i]
          DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %d) %s - %s remaining",
            i, e.zone or "?", format_mmss(e.expires - t)
          ))
        end
      end
    end
  end)

  -- Position wiederherstellen
  local bp = InstanceTrackerDB.btn
  container:ClearAllPoints()
  if bp and bp.point and bp.relativePoint and bp.x and bp.y then
    container:SetPoint(bp.point, UIParent, bp.relativePoint, bp.x, bp.y)
  else
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  end

  if InstanceTrackerDB.btn.shown == false then
    container:Hide()
  else
    container:Show()
  end
end

-- =======================
-- Slash-Commands: /it und /tt (remove 1-5)
-- =======================
SLASH_INSTANCETRACKER1 = "/it"
SLASH_INSTANCETRACKER2 = "/instancetracker"
SLASH_INSTANCETRACKER3 = "/tt"

SlashCmdList["INSTANCETRACKER"] = function(msg)
  IT_EnsureDB()
  local m = msg or ""
  local _, _, cmd, rest = string.find(m, "^(%S+)%s*(.*)$")
  cmd = string.lower(cmd or m or "")
  rest = string.lower(rest or "")

  if cmd == "remove" then
    local num = tonumber(rest)
    if num and num >= 1 and num <= 5 then
      if removeEntryByIndex(num) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: ID "..num.." entfernt.")
        if listFrame then IT_RefreshListFrame() end
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555"..ADDON_NAME.."|r: No ID at position "..num..".")
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: /it remove <1-5>")
    end
    return
  end

  if cmd == "clear" or cmd == "reset" then
    InstanceTrackerDB.entries = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: All entries cleared.")
    if listFrame then IT_RefreshListFrame() end

  elseif cmd == "show" or cmd == "button" then
    InstanceTrackerDB.btn.shown = true
    InstanceTracker_RecreateFloatingButton()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Button created/shown. Drag with left mouse button.")

  elseif cmd == "hide" then
    InstanceTrackerDB.btn.shown = false
    if InstanceTrackerFloatingButton then InstanceTrackerFloatingButton:Hide() end
    if listFrame then listFrame:Hide() end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Button hidden.")

  elseif cmd == "resetbtn" then
    InstanceTrackerDB.btn = { shown = true, locked = InstanceTrackerDB.btn.locked }
    InstanceTracker_RecreateFloatingButton()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Button position reset.")

  elseif cmd == "unlock" then
    InstanceTrackerDB.btn.locked = false
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON_NAME.."|r: Button unlocked. You can drag it to move.")

  elseif cmd == "lock" then
    InstanceTrackerDB.btn.locked = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Button locked.")

  elseif cmd == "list" or cmd == "" then
    pruneExpired()
    if tlen(InstanceTrackerDB.entries) == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: No active IDs.")
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r: Active IDs:")
    table.sort(InstanceTrackerDB.entries, function(a, b)
      return (a.expires - now()) < (b.expires - now())
    end)
    local t = now()
    local i
    for i = 1, tlen(InstanceTrackerDB.entries) do
      local e = InstanceTrackerDB.entries[i]
      DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "  %d) %s - %s remaining", i, e.zone or "?", format_mmss(e.expires - t)
      ))
    end

  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON_NAME.."|r Commands: /it [list], /it remove <1-5>, /it clear, /it show, /it hide, /it unlock, /it lock, /it resetbtn")
  end
end

-- =======================
-- Events
-- =======================
frame:SetScript("OnEvent", function()
  local evt = event
  local a1 = arg1

  if evt == "VARIABLES_LOADED" or evt == "PLAYER_LOGIN" then
    IT_EnsureDB()
    pruneExpired()
    InstanceTracker_RecreateFloatingButton()
    IT_CreateMinimapButton()
    saveCurrentInInstance()

  elseif evt == "PLAYER_ENTERING_WORLD" then
    pruneExpired()
    if not IT_Initialized then
      IT_Initialized = true
      saveCurrentInInstance()
    else
      onAfterLoadingScreen()
    end

  elseif evt == "ZONE_CHANGED_NEW_AREA" then
    onZoneChange()
  end
end)
