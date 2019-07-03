local addonName, addonTable = ...

local Data = LibStub('AceAddon-3.0'):NewAddon('Multiboxer_Data', 'AceEvent-3.0', 'AceHook-3.0', 'AceTimer-3.0')
addonTable[1] = Data
_G[addonName] = Data

local StdUi = LibStub('StdUi')


function Data:OnInitialize()
    self:InitDatabase()
end

function Data:OnEnable()
    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    self:RegisterEvent('CONSOLE_MESSAGE')
    self:RegisterEvent('CHAT_MSG_SYSTEM')

    self:RegisterEvent('BAG_UPDATE')
    self:RegisterEvent('PLAYER_MONEY')

    self:ScheduleRepeatingTimer('CheckInventory', 2)

    self:RawHook('SendMail', self.SendMailCheck, true)
end

function Data:PLAYER_ENTERING_WORLD()
    if not self.initialised then  
        self:InitCharDB()
    end
    self.initialised = true
end

-- handless skill rating increases
function Data:CONSOLE_MESSAGE(event, message)
    if strfind(message, 'Skill') then
        local _,skillLine,_,_,_,_,newRating = strsplit(' ', message)
        skillLine = tonumber(skillLine)
        newRating = tonumber(newRating)
        if self.charDB.professions[skillLine] then
            self.charDB.professions[skillLine] = newRating
        end
    end
end

-- handles learning new professions and or recipes
function Data:CHAT_MSG_SYSTEM(event, message)
    for professionName, professionData in pairs(self.professionData) do
        if strfind(message, professionName) then
            self:SetProfessions()
        end
        for recipeName, _ in pairs(professionData.recipes) do
            if strfind(message, recipeName) then
                self:SetRecipeRanks()
            end
        end
    end
end

function Data:BAG_UPDATE(bagID)
    self.bagEvent = true
end

function Data:PLAYER_MONEY()

end


function Data:InitDatabase()
    if not Multiboxer_DataDB or type(Multiboxer_DataDB) ~= 'table' then
        Multiboxer_DataDB = {}
    end
    self.db = Multiboxer_DataDB

    self.charLevel = UnitLevel('player')
    self.charName = UnitName('player')
    self.realmName = GetRealmName()
    self.fullName = self.charName .. '-' .. self.realmName

    -- db schema
    self.db.charData = self.db.charData or {}
    self.charDB = self.db.charData[self.fullName] or {}
    
    self.realmData = self.db.realmData[self.realmName] or {}
    self.db.realmData[self.realmName] = self.realmData

    self.itemData = self.realmData.itemData or {}
    self.realmData.itemData = self.itemData

    self.mailData = self.realmData.mailData or {}
    self.realmData.mailData = self.mailData
    self.mailData.sentMails = self.mailData.sentMails or {}
    self.mailData.openedMails = self.mailData.openedMails or {}

    -- tracking data
    self.itemIDs = self.itemIDs or {}
    self.professionData = self.professionData or {}
end

function Data:InitCharDB()
    -- profession info is relevant for level 111+ chars only
    if self.charLevel < 111 then return end
    
    -- nazjatar intro completed
    if not self.charDB.introCompleted then
        self.charDB.introCompleted = IsQuestFlaggedCompleted(55053)
    end
    -- professions and ratings
    if not self.charDB.professions then
        self:SetProfessions()
    end
    -- recipe ranks
    if not self.charDB.recipeRanks then
        self:SetRecipeRanks() -- no param to start the chain
    end
    -- add profile to db
    self.db.charData[self.fullName] = self.charDB
end

function Data:SetProfessions()
    self.charDB.professions = {}
    local prof1, prof2 = GetProfessions()
    for _, tabIndex in ipairs({prof1, prof2}) do
        local name,_,_,_,_,_,skillLine = GetProfessionInfo(tabIndex)
        if self.professionData[name] then
            self.charDB.professions[skillLine] = true
            local expSkillLine = self.professionData[name].skillLines.expansion
            expName, expRank = C_TradeSkillUI.GetTradeSkillLineInfoByID(expSkillLine)
            self.charDB.professions[expSkillLine] = expRank 
        end
    end
end

-- Use without parameter to initiate an all profession check
function Data:SetRecipeRanks(profession)  
    -- checks recipe ranks for next profession in list
    local function SetNextProfessionRecipeRanks()
        if next(self.professionsToCheck) then
            local professionName = tremove(self.professionsToCheck)
            C_TradeSkillUI.OpenTradeSkill(self.professionData[professionName].skillLines.main)
            C_Timer.After(0.1, function() self:SetRecipeRanks(professionName) end)
        end
    end

    -- no parameter means we start here and recursively call the function for each profession
    if not profession then
        self.charDB.recipeRanks = {}
        -- create list of profession names to check (tracked and learned)
        self.professionsToCheck = {}
        for profession, data in pairs(self.professionData) do
            if self.charDB.professions[data.skillLines.expansion] then
                tinsert(self.professionsToCheck, profession)
            end
        end
        SetNextProfessionRecipeRanks()
        return
    end

    for recipeName, recipeID in pairs(self.professionData[profession].recipes) do
        local recipeRank = 0
        local id = recipeID
        while(id) do
            local recipeInfo = C_TradeSkillUI.GetRecipeInfo(id)
            if recipeInfo and recipeInfo.learned then
                recipeRank = GetSpellRank(id)
                break
            elseif recipeInfo and recipeInfo.previousRecipeID then
                id = recipeInfo.previousRecipeID
            else
                break
            end
        end
        self.charDB.recipeRanks[recipeName] = recipeRank
        print(recipeName, recipeRank)
    end
    -- close window and check next profession
    C_TradeSkillUI.CloseTradeSkill()
    SetNextProfessionRecipeRanks()
end


function Data:CheckInventory()
    if not self.bagEvent then return end
    self.bagEvent = false

    local charItemData = {}
    for itemID, _ in pairs(self.itemIDs) do
        local itemCount = GetItemCount(itemID, true)
        if itemCount > 0 then
            charItemData[itemID] = itemCount
        end
    end 
    
    if next(charItemData) then
        self.itemData[self.fullName] = charItemData
    end
end

function Data.SendMailCheck(target, subject, body)
    local mailInfo = {}

    local sentItems = {}
    for i = 1, 12 do
        local itemName, itemID, _, count = GetSendMailItem(i)
        if Data.trackedItems[itemID] then
            sentItems[itemID] = sentItems[itemID] or 0
            sentItems[itemID] = sentItems[itemID] + count
        end
    end
    table.foreach(sentItems, print)
    print(#sentItems)
    -- don't store info about this mail
    if not next(sentItems) then 
        print('nothing important sent')
        Data.hooks.SendMail(target, subject, body)
        return
    end
    mailInfo.sentItems = sentItems
    mailInfo.timestamp = time()
    mailInfo.target = target

    Data:AddMailEntry(mailInfo)

    Data.hooks.SendMail(target, subject, body)
end

function Data:AddMailEntry(mailInfo)
    tinsert(self.charDB, mailInfo)

    if not self.db[self.profileName] then
        self.db[self.profileName] = self.charDB
    end
end


