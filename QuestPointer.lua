local addonName = ...
local db, options, category, closeMenu, OpenOptions
local driver = CreateFrame("Frame")
local arrow = CreateFrame("Frame", "QuestPointerArrow", UIParent)
arrow:SetPoint("TOP", UIParent, "TOP", 0, -150)
arrow:SetFrameStrata("HIGH")
arrow:EnableMouse(true)
arrow:SetMovable(true)
arrow:SetClampedToScreen(true)
arrow:RegisterForDrag("LeftButton")
local graphic = arrow:CreateTexture(nil, "ARTWORK")
graphic:SetAllPoints()
graphic:SetTexture("Interface\\AddOns\\QuestPointer\\Media\\Arrow.tga")
arrow:Hide()
local distanceText = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
distanceText:SetPoint("TOP", arrow, "BOTTOM", 0, -6)
distanceText:SetWidth(300)
distanceText:SetJustifyH("CENTER")
distanceText:SetText("Distance unavailable")
local objectiveText = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
objectiveText:SetPoint("TOP", distanceText, "BOTTOM", 0, -4)
objectiveText:SetWidth(300)
objectiveText:SetJustifyH("CENTER")
objectiveText:SetSpacing(3)
objectiveText:SetWordWrap(true)

local function PublicNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

local function ApplySize(size)
    db.size = math.floor(math.max(24, math.min(160, size)) + 0.5)
    arrow:SetSize(db.size, db.size)
end

local function ApplyColor()
    local hue = (db.hue % 360) / 60
    local sector = math.floor(hue)
    local fraction = hue - sector
    local colors = {
        {1, fraction, 0}, {1 - fraction, 1, 0}, {0, 1, fraction},
        {0, 1 - fraction, 1}, {fraction, 0, 1}, {1, 0, 1 - fraction},
    }
    local rgb = colors[sector + 1]
    graphic:SetVertexColor(rgb[1], rgb[2], rgb[3])
end

local function ApplyGraphic()
    local file = db.style == "perspective" and "Arrow3D.tga" or "Arrow.tga"
    graphic:SetTexture("Interface\\AddOns\\QuestPointer\\Media\\" .. file)
    graphic:SetTexCoord(0, 1, 0, 1)
    graphic:SetRotation(0)
    ApplyColor()
end

local function RenderDirection(angle)
    if db.style == "perspective" then
        local cell = math.floor((angle % (2 * math.pi)) / (2 * math.pi) * 64 + 0.5) % 64
        local column, row = cell % 8, math.floor(cell / 8)
        graphic:SetRotation(0)
        graphic:SetTexCoord(column / 8, (column + 1) / 8, row / 8, (row + 1) / 8)
    else
        graphic:SetTexCoord(0, 1, 0, 1)
        graphic:SetRotation(angle)
    end
end

local navigation = {status = "Waiting for location data"}
local function Call(label, func, ...)
    if type(func) ~= "function" then navigation[label] = "API unavailable"; return end
    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        navigation[label] = "API error: " .. tostring(a)
        return
    end
    local function Describe(v)
        if issecretvalue and issecretvalue(v) then return "restricted" end
        if type(v) == "table" and v.GetXY then
            local vx, vy = v:GetXY()
            if PublicNumber(vx) and PublicNumber(vy) then return string.format("(%.4f, %.4f)", vx, vy) end
            return "vector unavailable"
        end
        return tostring(v)
    end
    navigation[label] = table.concat({Describe(a), Describe(b), Describe(c), Describe(d)}, ", ")
    return a, b, c, d
end
local function ValidPoint(x, y)
    return PublicNumber(x) and PublicNumber(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local poiCache = {}
local function FindQuestMapMarker(questID, playerMap)
    local maps, seen = {}, {}
    local function AddMap(id)
        if PublicNumber(id) and id > 0 and not seen[id] then
            seen[id] = true
            maps[#maps + 1] = id
        end
    end
    AddMap(playerMap)
    AddMap(Call("Quest UI map", C_QuestLog and C_QuestLog.GetQuestUiMapID, questID))
    -- Include parent maps so objectives across a zone boundary are discoverable.
    local current = playerMap
    for _ = 1, 4 do
        local info = Call("Map parent", C_Map and C_Map.GetMapInfo, current)
        if type(info) ~= "table" or not PublicNumber(info.parentMapID) or info.parentMapID <= 0 then break end
        current = info.parentMapID
        if seen[current] then break end
        AddMap(current)
    end
    local report = {}
    for _, queryMap in ipairs(maps) do
        local now = GetTime and GetTime() or 0
        local cached = poiCache[queryMap]
        local quests
        if cached and now > 0 and now - cached.time < 0.5 then
            quests = cached.quests
        else
            quests = Call("Map quest markers", C_QuestLog and C_QuestLog.GetQuestsOnMap, queryMap)
            poiCache[queryMap] = {time = now, quests = quests}
        end
        report[#report + 1] = tostring(queryMap) .. "=" .. (type(quests) == "table" and tostring(#quests) or "nil")
        if type(quests) == "table" then
            for _, poi in ipairs(quests) do
                if PublicNumber(poi.questID) and poi.questID == questID and ValidPoint(poi.x, poi.y)
                    and not poi.isQuestStart then
                    navigation["Map marker lookup"] = table.concat(report, "; ")
                    navigation["Location source"] = "Quest map marker on map " .. queryMap
                    -- Marker x/y are normalized to the map queried, including
                    -- when a parent map projects a marker from a child zone.
                    return queryMap, poi.x, poi.y
                end
            end
        end
    end
    navigation["Map marker lookup"] = table.concat(report, "; ") .. "; no matching objective marker"
end

local lastObjectiveQuest, lastObjectiveTime
local function UpdateObjectives(questID)
    local now = GetTime and GetTime() or 0
    if questID == lastObjectiveQuest and now > 0 and lastObjectiveTime and now - lastObjectiveTime < 0.25 then return end
    lastObjectiveQuest, lastObjectiveTime = questID, now
    if not questID then objectiveText:SetText(""); return end
    local objectives = Call("Quest objectives", C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    local lines = {}
    if type(objectives) == "table" then
        for _, objective in ipairs(objectives) do
            local text = objective.text
            if not (issecretvalue and issecretvalue(text)) and type(text) == "string" and text ~= "" then
                local fulfilled, required = objective.numFulfilled, objective.numRequired
                -- Move the game's trailing counter to the beginning; preserve
                -- objective wording and avoid displaying the counter twice.
                local name, current, total = text:match("^(.-):?%s+(%d+)%s*/%s*(%d+)%s*$")
                if name then name = name:gsub(":%s*$", "") end
                local prefixCurrent, prefixTotal, prefixName = text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
                if prefixName then name, current, total = prefixName, prefixCurrent, prefixTotal end
                if PublicNumber(fulfilled) and PublicNumber(required) and required > 0
                    and (current or required > 1 or objective.type == "monster" or objective.type == "item" or objective.type == "object") then
                    text = string.format("%d/%d %s", fulfilled, required, name or text)
                elseif current and total then
                    text = current .. "/" .. total .. " " .. name
                end
                lines[#lines + 1] = text
            end
        end
    end
    -- Delivery/report quests can have no leaderboard objectives at all.
    -- Read their narrative objective without changing the selected quest.
    if #lines == 0 then
        local text = Call("Waypoint objective text", C_QuestLog and C_QuestLog.GetNextWaypointText, questID)
        local function Usable(value)
            return not (issecretvalue and issecretvalue(value)) and type(value) == "string" and value:match("%S")
        end
        if not Usable(text) then
            local index = Call("Quest log index", C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
            if PublicNumber(index) and index > 0 then
                local _, summary = Call("Quest objective summary", GetQuestLogQuestText, index)
                text = summary
                if not Usable(text) then
                    text = Call("Quest completion objective", GetQuestLogCompletionText, index)
                end
            end
        end
        if Usable(text) then lines[#lines + 1] = text end
    end
    objectiveText:SetText(table.concat(lines, "\n"))
end

local function UpdateArrow()
    if not db then return end
    if db.closed then arrow:Hide(); return end
    navigation = {}
    local function Unavailable(reason)
        navigation.status = reason
        distanceText:SetText(reason == "At objective location" and "0 yards" or "Distance unavailable")
        RenderDirection(0)
        graphic:SetAlpha(0.4)
        arrow:Show()
    end
    local tracked = Call("Supertracked quest", C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
    local selected = Call("Selected quest", C_QuestLog and C_QuestLog.GetSelectedQuest)
    local questID = tracked
    if not PublicNumber(questID) or questID <= 0 then questID = selected end
    if not PublicNumber(questID) or questID <= 0 then
        UpdateObjectives(nil)
        Unavailable("No active quest ID"); return
    end
    UpdateObjectives(questID)
    navigation.questID = questID
    local playerMap = Call("Player map", C_Map and C_Map.GetBestMapForUnit, "player")
    if not PublicNumber(playerMap) then Unavailable("Player map unavailable"); return end
    local mapID, x, y
    if questID == tracked then
        x, y = Call("Supertracker waypoint", C_SuperTrack and C_SuperTrack.GetNextWaypointForMap, playerMap)
        if ValidPoint(x, y) then mapID = playerMap end
    end
    if not mapID then
        x, y = Call("Quest waypoint on player map", C_QuestLog and C_QuestLog.GetNextWaypointForMap, questID, playerMap)
        if ValidPoint(x, y) then mapID = playerMap end
    end
    if not mapID then
        mapID, x, y = Call("Quest next waypoint", C_QuestLog and C_QuestLog.GetNextWaypoint, questID)
    end
    if not PublicNumber(mapID) or not ValidPoint(x, y) then
        mapID, x, y = FindQuestMapMarker(questID, playerMap)
    end
    if not PublicNumber(mapID) or not ValidPoint(x, y) then
        Unavailable("No waypoint or map objective marker for active quest"); return
    end
    navigation.target = string.format("map %d, %.4f, %.4f", mapID, x, y)
    local instance, target = Call("Objective world position", C_Map and C_Map.GetWorldPosFromMapPos,
        mapID, CreateVector2D(x, y))
    local playerPosition = Call("Player map position", C_Map and C_Map.GetPlayerMapPosition, playerMap, "player")
    if not playerPosition then Unavailable("Player map position unavailable"); return end
    local playerInstance, playerWorld = Call("Player world position", C_Map and C_Map.GetWorldPosFromMapPos,
        playerMap, playerPosition)
    local facing = Call("Player facing", GetPlayerFacing)
    if not target or not playerWorld then Unavailable("Map-to-world conversion unavailable"); return end
    if not PublicNumber(facing) then Unavailable("Player facing unavailable or restricted"); return end
    if not PublicNumber(instance) or not PublicNumber(playerInstance) or instance ~= playerInstance then
        Unavailable("Objective and player are in different world instances"); return
    end
    local tx, ty = target:GetXY()
    local px, py = playerWorld:GetXY()
    if not PublicNumber(tx) or not PublicNumber(ty) or not PublicNumber(px) or not PublicNumber(py) then
        Unavailable("World coordinates unavailable or restricted"); return
    end
    local north, west = tx - px, ty - py
    local distance = math.sqrt(north * north + west * west)
    if distance < 1 then Unavailable("At objective location"); return end
    distanceText:SetText(string.format("%d yards", math.floor(distance + 0.5)))
    local rotation = math.atan2(west, north) - facing
    RenderDirection(rotation)
    graphic:SetAlpha(1)
    navigation.status = "Tracking"
    navigation.rotation = string.format("%.2f degrees", rotation * 180 / math.pi)
    arrow:Show()
end

local function DebugNavigation()
    UpdateArrow()
    local lines = {"QuestPointer 1.1.0", "Status: " .. (navigation.status or "Unknown")}
    if GetBuildInfo then
        local version, build, _, interface = GetBuildInfo()
        lines[#lines + 1] = "Client: " .. tostring(version) .. ", build " .. tostring(build) .. ", interface " .. tostring(interface)
    end
    local labels = {"Supertracked quest", "Selected quest", "questID", "Player map",
        "Supertracker waypoint", "Quest waypoint on player map", "Quest next waypoint", "target",
        "Location source", "Quest UI map", "Map marker lookup", "Map quest markers",
        "Objective world position", "Player map position", "Player world position", "Player facing", "rotation"}
    for _, label in ipairs(labels) do
        if navigation[label] then lines[#lines + 1] = label .. ": " .. tostring(navigation[label]) end
    end
    for _, line in ipairs(lines) do print(line) end
end

local function CloseArrow()
    db.closed = true
    arrow:Hide()
    if closeMenu then closeMenu:Hide() end
end

local function RestorePosition()
    arrow:ClearAllPoints()
    if PublicNumber(db.x) and PublicNumber(db.y) then
        arrow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.x, db.y)
    else
        arrow:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

local function StopDragging()
    if not arrow.dragging then return end
    arrow:StopMovingOrSizing()
    arrow.dragging = false
    local x, y = arrow:GetCenter()
    if PublicNumber(x) and PublicNumber(y) then
        db.x, db.y = x, y
        RestorePosition()
    end
end

local function ToggleLock()
    StopDragging()
    db.locked = not db.locked
end

local function ResetPosition()
    StopDragging()
    db.x, db.y = nil, nil
    RestorePosition()
end

local function MenuEntries()
    return {
        {"Options", function() OpenOptions() end},
        {db.locked and "Unlock Arrow" or "Lock Arrow", ToggleLock},
        {"Reset Position", ResetPosition},
        {"Close", CloseArrow},
    }
end

-- Compatibility context menu for clients without retail's MenuUtil.
-- Rows are flat, highlighted menu entries, not dialog buttons.
closeMenu = CreateFrame("Frame", "QuestPointerContextMenu", UIParent, "BackdropTemplate")
closeMenu:SetSize(170, 120)
closeMenu:SetFrameStrata("TOOLTIP")
closeMenu:SetClampedToScreen(true)
closeMenu:EnableMouse(true)
closeMenu:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}})
closeMenu:SetBackdropColor(0.08, 0.08, 0.08, 1)
closeMenu:Hide()
table.insert(UISpecialFrames, "QuestPointerContextMenu")
local menuTitle = closeMenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
menuTitle:SetPoint("TOPLEFT", 12, -10)
menuTitle:SetText("QuestPointer")
local menuRows = {}
for i = 1, 4 do
    local row = CreateFrame("Button", nil, closeMenu)
    row:SetSize(150, 20)
    row:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 20)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 5, 0)
    row.label = label
    menuRows[i] = row
end
closeMenu:SetScript("OnUpdate", function()
    if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
        and not closeMenu:IsMouseOver() and not arrow:IsMouseOver() then
        closeMenu:Hide()
    end
end)

local function OpenContextMenu()
    StopDragging()
    local entries = MenuEntries()
    if MenuUtil and MenuUtil.CreateContextMenu then
        closeMenu:Hide()
        MenuUtil.CreateContextMenu(arrow, function(_, root)
            root:CreateTitle("QuestPointer")
            for _, entry in ipairs(entries) do root:CreateButton(entry[1], entry[2]) end
        end)
    else
        for i, entry in ipairs(entries) do
            local callback = entry[2]
            menuRows[i].label:SetText(entry[1])
            menuRows[i]:SetScript("OnClick", function() closeMenu:Hide(); callback() end)
        end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        closeMenu:ClearAllPoints()
        closeMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        closeMenu:SetShown(not closeMenu:IsShown())
    end
end
arrow:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then OpenContextMenu() end
end)
arrow:SetScript("OnDragStart", function()
    if not db or db.locked then return end
    closeMenu:Hide()
    arrow.dragging = true
    arrow:StartMoving()
end)
arrow:SetScript("OnDragStop", StopDragging)
arrow:SetScript("OnHide", function() StopDragging(); closeMenu:Hide() end)

local profileFields = {"size", "style", "hue", "opacity", "locked", "closed", "x", "y"}
local function SaveProfile(name)
    local profile = {}
    for _, field in ipairs(profileFields) do profile[field] = db[field] end
    QuestPointerProfiles[name] = profile
end
local function LoadProfile(name)
    local profile = QuestPointerProfiles[name]
    if type(profile) ~= "table" then return false end
    StopDragging()
    for _, field in ipairs(profileFields) do db[field] = profile[field] end
    db.opacity = PublicNumber(db.opacity) and math.max(0, math.min(1, db.opacity)) or 1
    ApplySize(PublicNumber(db.size) and db.size or 64)
    ApplyGraphic()
    arrow:SetAlpha(db.opacity)
    RestorePosition()
    UpdateArrow()
    return true
end

local function BuildOptions()
    options = CreateFrame("Frame", "QuestPointerOptions", UIParent)
    options.name = "QuestPointer"
    options:Hide()
    local title = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("QuestPointer — Appearance")
    local description = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", 16, -46)
    description:SetText("Arrow appearance and positioning. Settings are saved per character.")
    local heading = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 16, -82)
    heading:SetText("Arrow graphic")
    local choices = {}
    local styles = {{"simple", "2D Simple"}, {"perspective", "3D"}}
    local function RefreshChoices()
        for i, choice in ipairs(choices) do choice:SetChecked(db.style == styles[i][1]) end
    end
    for i, style in ipairs(styles) do
        local id, label = style[1], style[2]
        local button = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
        button:SetPoint("TOPLEFT", 16, -102 - (i - 1) * 34)
        button:SetSize(28, 28)
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        text:SetText(label)
        button:SetScript("OnClick", function()
            db.style = id
            ApplyGraphic()
            RefreshChoices()
            UpdateArrow()
        end)
        choices[i] = button
    end
    local hint = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -182)
    hint:SetText("3D: up points away from you; down points back toward you.")
    local colorHeading = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorHeading:SetPoint("TOPLEFT", 16, -216)
    colorHeading:SetText("Arrow color")
    local colorSlider = CreateFrame("Slider", "QuestPointerColorSlider", options, "OptionsSliderTemplate")
    colorSlider:SetPoint("TOPLEFT", 24, -252)
    colorSlider:SetWidth(280)
    colorSlider:SetMinMaxValues(0, 360)
    colorSlider:SetValueStep(1)
    colorSlider:SetObeyStepOnDrag(true)
    QuestPointerColorSliderLow:SetText("Red")
    QuestPointerColorSliderHigh:SetText("Red")
    colorSlider:SetScript("OnValueChanged", function(_, value)
        db.hue = math.floor(value + 0.5)
        ApplyColor()
        local names = {"Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Pink", "Red"}
        local index = math.floor(db.hue / 45 + 0.5) + 1
        QuestPointerColorSliderText:SetText(names[index])
    end)
    local sizeHeading = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeHeading:SetPoint("TOPLEFT", 16, -304)
    sizeHeading:SetText("Arrow size")
    local slider = CreateFrame("Slider", "QuestPointerSizeSlider", options, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 24, -340)
    slider:SetWidth(280)
    slider:SetMinMaxValues(24, 160)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    QuestPointerSizeSliderLow:SetText("24")
    QuestPointerSizeSliderHigh:SetText("160")
    slider:SetScript("OnValueChanged", function(_, value)
        ApplySize(value)
        QuestPointerSizeSliderText:SetText(db.size .. " pixels")
    end)
    local locked = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
    locked:SetPoint("TOPLEFT", 16, -384)
    locked:SetSize(28, 28)
    local lockLabel = locked:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lockLabel:SetPoint("LEFT", locked, "RIGHT", 4, 0)
    lockLabel:SetText("Lock arrow position")
    locked:SetScript("OnClick", function() StopDragging(); db.locked = locked:GetChecked() == true end)
    local visible = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
    visible:SetPoint("TOPLEFT", 16, -418)
    visible:SetSize(28, 28)
    local visibleLabel = visible:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    visibleLabel:SetPoint("LEFT", visible, "RIGHT", 4, 0)
    visibleLabel:SetText("Show arrow")
    visible:SetScript("OnClick", function()
        if visible:GetChecked() then db.closed = false; UpdateArrow() else CloseArrow() end
    end)
    local reset = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    reset:SetSize(130, 24)
    reset:SetPoint("TOPLEFT", 16, -466)
    reset:SetText("Reset size")
    reset:SetScript("OnClick", function() slider:SetValue(64) end)
    local resetPosition = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    resetPosition:SetSize(150, 24)
    resetPosition:SetPoint("LEFT", reset, "RIGHT", 12, 0)
    resetPosition:SetText("Reset position")
    resetPosition:SetScript("OnClick", ResetPosition)
    local alphaHeading = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaHeading:SetPoint("TOPLEFT", 360, -82)
    alphaHeading:SetText("Transparency")
    local alphaSlider = CreateFrame("Slider", "QuestPointerTransparencySlider", options, "OptionsSliderTemplate")
    alphaSlider:SetPoint("TOPLEFT", 368, -118)
    alphaSlider:SetWidth(220)
    alphaSlider:SetMinMaxValues(0, 100)
    alphaSlider:SetValueStep(1)
    alphaSlider:SetObeyStepOnDrag(true)
    QuestPointerTransparencySliderLow:SetText("Opaque")
    QuestPointerTransparencySliderHigh:SetText("Invisible")
    alphaSlider:SetScript("OnValueChanged", function(_, value)
        db.opacity = 1 - value / 100
        arrow:SetAlpha(db.opacity)
        QuestPointerTransparencySliderText:SetText(string.format("%d%%", math.floor(value + 0.5)))
    end)
    local profilesPage = CreateFrame("Frame", "QuestPointerProfilesOptions", UIParent)
    profilesPage.name = "Profiles"
    profilesPage:Hide()
    local profileHeading = profilesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileHeading:SetPoint("TOPLEFT", 16, -16)
    profileHeading:SetText("Shared profiles")
    local help = profilesPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -48)
    help:SetWidth(440)
    help:SetJustifyH("LEFT")
    help:SetText("Save these settings with a name, then load them on another character. Loading copies settings to this character.")
    local nameBox = CreateFrame("EditBox", "QuestPointerProfileName", profilesPage, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", 24, -126)
    nameBox:SetSize(220, 24)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local nameLabel = profilesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 16, -98)
    nameLabel:SetText("Profile name")
    local save = CreateFrame("Button", "QuestPointerSaveProfile", profilesPage, "UIPanelButtonTemplate")
    save:SetPoint("TOPLEFT", 16, -162)
    save:SetSize(240, 24)
    save:SetText("Save / overwrite named profile")
    local selectionLabel = profilesPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectionLabel:SetPoint("TOPLEFT", 16, -212)
    selectionLabel:SetText("Saved profiles")
    local selectedProfile
    local chooser = CreateFrame("DropdownButton", "QuestPointerChooseProfile", profilesPage, "WowStyle1DropdownTemplate")
    chooser:SetPoint("TOPLEFT", 16, -240)
    chooser:SetSize(240, 24)
    local function RefreshProfiles()
        if selectedProfile and QuestPointerProfiles[selectedProfile] then
            chooser:OverrideText(selectedProfile)
        else
            selectedProfile = nil
            chooser:OverrideText("Choose a saved profile")
        end
    end
    local function Choose(name)
        selectedProfile = name
        nameBox:SetText(name)
        RefreshProfiles()
    end
    chooser:SetDefaultText("Choose a saved profile")
    chooser:SetupMenu(function(_, root)
        local names = {}
        for name in pairs(QuestPointerProfiles) do names[#names + 1] = name end
        table.sort(names)
        if #names == 0 then root:CreateTitle("No saved profiles"); return end
        root:SetScrollMode(300)
        for _, name in ipairs(names) do
            root:CreateRadio(name,
                function(value) return selectedProfile == value end,
                function(value) Choose(value) end, name)
        end
    end)
    save:SetScript("OnClick", function()
        local name = (nameBox:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then nameBox:SetFocus(); return end
        SaveProfile(name)
        Choose(name)
        nameBox:ClearFocus()
    end)
    local load = CreateFrame("Button", "QuestPointerLoadProfile", profilesPage, "UIPanelButtonTemplate")
    load:SetPoint("TOPLEFT", 16, -282)
    load:SetSize(240, 24)
    load:SetText("Load selected profile")
    local function RefreshControls()
        RefreshChoices()
        slider:SetValue(db.size)
        colorSlider:SetValue(db.hue)
        alphaSlider:SetValue((1 - db.opacity) * 100)
        locked:SetChecked(db.locked)
        visible:SetChecked(not db.closed)
    end
    profilesPage:SetScript("OnShow", RefreshProfiles)
    load:SetScript("OnClick", function()
        if selectedProfile and LoadProfile(selectedProfile) then RefreshProfiles() end
    end)
    options:SetScript("OnShow", RefreshControls)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(options, "QuestPointer")
        Settings.RegisterAddOnCategory(category)
        Settings.RegisterCanvasLayoutSubcategory(category, profilesPage, "Profiles")
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(options)
        profilesPage.parent = "QuestPointer"
        InterfaceOptions_AddCategory(profilesPage)
    end
end

OpenOptions = function()
    closeMenu:Hide()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(options)
    else
        print("QuestPointer: open Options > AddOns > QuestPointer.")
    end
end

SLASH_QUESTPOINTER1 = "/questpointer"
SLASH_QUESTPOINTER2 = "/qp"
SlashCmdList.QUESTPOINTER = function(message)
    if not options then return end
    message = (message or ""):match("^%s*(.-)%s*$"):lower()
    if message == "debug" then
        DebugNavigation()
    elseif message == "close" then
        CloseArrow()
    else
        db.closed = false
        OpenOptions()
        UpdateArrow()
    end
end

driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then return end
    QuestPointerDB = type(QuestPointerDB) == "table" and QuestPointerDB or {}
    db = QuestPointerDB
    QuestPointerProfiles = type(QuestPointerProfiles) == "table" and QuestPointerProfiles or {}
    db.opacity = PublicNumber(db.opacity) and math.max(0, math.min(1, db.opacity)) or 1
    arrow:SetAlpha(db.opacity)
    ApplySize(type(db.size) == "number" and db.size or 64)
    if not PublicNumber(db.hue) then db.hue = db.style == "red" and 0 or 45 end
    db.hue = math.max(0, math.min(360, db.hue))
    if db.style ~= "perspective" then db.style = "simple" end
    ApplyGraphic()
    db.locked = db.locked == true
    RestorePosition()
    BuildOptions()
    driver:UnregisterEvent("ADDON_LOADED")
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.03 then return end
        elapsed = 0
        UpdateArrow()
    end)
end)
