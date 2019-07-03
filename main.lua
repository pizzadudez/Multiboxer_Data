local addonName, addonTable = ...

local Data = LibStub('AceAddon-3.0'):NewAddon('Multiboxer_Data', 'AceEvent-3.0', 'AceHook-3.0', 'AceTimer-3.0')
addonTable[1] = Data
_G[addonName] = Data

local StdUi = LibStub('StdUi')


-- ============================================================================
-- Addon Initialization
-- ============================================================================

function Data:OnInitialize()
    self:InitDatabase()
end

function Data:OnEnable()
    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    self:RegisterEvent('CONSOLE_MESSAGE')
    self:RegisterEvent('CHAT_MSG_SYSTEM')

    self:RegisterEvent('BAG_UPDATE')
    self:RegisterEvent('PLAYER_MONEY')
    
    -- Bag updating
    self:ScheduleRepeatingTimer('CheckInventory', 2)

    -- Mail Hooks
    self:RawHook('SendMail', self.CheckSendMail, true)
    self:RawHook('AutoLootMailItem', self.CheckAutoLootMailItem, true)
    self:RawHook('TakeInboxItem', self.CheckTakeInboxItem, true)
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
    
    self.db.realmData = self.db.realmData or {}
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


-- ============================================================================
-- Event Handlers
-- ============================================================================

function Data:PLAYER_ENTERING_WORLD()
    if not self.initialised then  
        self:InitCharDB()
    end
    self.initialised = true
end

-- used for skill rating increases in professions
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

-- used for updating professions and recipe ranks
function Data:CHAT_MSG_SYSTEM(event, message)
    for professionName, professionData in pairs(self.professionData) do
        if strfind(message, professionName) then
            self:SetProfessionInfo()
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
    print('bag event')
end

function Data:PLAYER_MONEY()
    -- TODO
end


-- ============================================================================
-- Character Profession Data
-- ============================================================================

function Data:InitCharDB()
    -- profession info is relevant for level 111+ chars only
    if self.charLevel < 111 then return end
    
    -- nazjatar intro completed
    if not self.charDB.introCompleted then
        self.charDB.introCompleted = IsQuestFlaggedCompleted(55053)
    end
    -- professions and ratings
    if not self.charDB.professions then
        self:SetProfessionInfo()
    end
    -- recipe ranks
    if not self.charDB.recipeRanks then
        self:SetRecipeRanks() -- no param to start the chain
    end
    -- add profile to db
    self.db.charData[self.fullName] = self.charDB
end

function Data:SetProfessionInfo()
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

-- Use without parameter to check all tracked professions
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


-- ============================================================================
-- Mail and Inventory
-- ============================================================================

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

    -- set itemData to nil instead of {}
    if not next(charItemData) then
        charItemData = nil
    end
        
    self.itemData[self.fullName] = charItemData
end

function Data.CheckSendMail(target, subject, body)
    local attachedItems = {}
    for i = 1, 12 do
        local _,itemID,_,count = GetSendMailItem(i)
        if Data.itemIDs[itemID] then
            attachedItems[itemID] = attachedItems[itemID] or 0
            attachedItems[itemID] = attachedItems[itemID] + count
        end
    end

    -- No tracked items sent, don't store this mail
    if not next(attachedItems) then 
        print('nothing important sent')
        Data.hooks.SendMail(target, subject, body)
        return
    end
    
    -- add mail to db
    local mailInfo = {}
    mailInfo.sender = Data.charName
    mailInfo.target = strmatch(target, '%a+') -- strip realm name
    mailInfo.sent = time()
    mailInfo.attachedItems = attachedItems
    local hashKey = strjoin('_', mailInfo.target, mailInfo.sender, mailInfo.sent)
    Data.mailData.sentMails[hashKey] = mailInfo

    -- we're done, call the original function
    Data.hooks.SendMail(target, mailInfo.sent, body)
end

function Data.CheckAutoLootMailItem(index)
    local _,_,sender,subject = GetInboxHeaderInfo(index)
    local _,_,_,_,isInvoice = GetInboxText(index)
    local timestamp = tonumber(subject)

    if isInvoice or not timestamp or timestamp > time() then
        Data.hooks.AutoLootMailItem(index)
        return
    end

    local attachedItems = {}
    for i = 1, 12 do
        local _,itemID,_,count = GetInboxItem(index, i)
        if Data.itemIDs[itemID] then
            attachedItems[itemID] = attachedItems[itemID] or 0
            attachedItems[itemID] = attachedItems[itemID] + count
        end
    end
    table.foreach(attachedItems, print)

    -- add mail to db
    local mailInfo = {}
    mailInfo.sender = strmatch(sender, '%a+') -- strip realm name 
    mailInfo.target = Data.charName
    mailInfo.sent = timestamp
    mailInfo.opened = time()
    mailInfo.attachedItems = attachedItems
    table.foreach(mailInfo, print)
    local hashKey = strjoin('_', mailInfo.target, mailInfo.sender, mailInfo.sent)
    Data.mailData.openedMails[hashKey] = mailInfo

    -- we're done, call the original function
    Data.hooks.AutoLootMailItem(index)
end

function Data.CheckTakeInboxItem(index, itemIndex)
    local _,_,sender,subject = GetInboxHeaderInfo(index)
    local _,_,_,_,isInvoice = GetInboxText(index)
    local timestamp = tonumber(subject)

    if isInvoice or not timestamp or timestamp > time() then
        Data.hooks.TakeInboxItem(index, itemIndex)
        return
    end
    
    -- attached item
    local _,itemID,_,count = GetInboxItem(index, itemIndex)

    local mailInfo = {}
    mailInfo.sender = strmatch(sender, '%a+') -- strip realm name 
    mailInfo.target = Data.charName
    mailInfo.sent = timestamp
    mailInfo.opened = time()
    mailInfo.attachedItems = {[itemID] = count}
    local hashKey = strjoin('_', mailInfo.target, mailInfo.sender, mailInfo.sent)

    -- add mail to db
    if not Data.mailData.openedMails[hashKey] then
        Data.mailData.openedMails[hashKey] = mailInfo
    else -- if mail already in db
        local openedMail = Data.mailData.openedMails[hashKey]
        openedMail.opened = mailInfo.opened
        openedMail.attachedItems[itemID] = openedMail.attachedItems[itemID] or 0
        openedMail.attachedItems[itemID] = openedMail.attachedItems[itemID] + count
    end

    -- we're done, call the original function
    Data.hooks.TakeInboxItem(index, itemIndex)
end