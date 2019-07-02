local addonName, addonTable = ...

local Data = LibStub('AceAddon-3.0'):NewAddon('Multiboxer_Data', 'AceEvent-3.0', 'AceHook-3.0')
addonTable[1] = Data
_G[addonName] = Data

local StdUi = LibStub('StdUi')


function Data:OnInitialize()
    self:InitDatabase()
end

function Data:OnEnable()
    self:RawHook('SendMail', self.SendMailCheck, true)
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

function Data:InitDatabase()
    if not Multiboxer_DataDB or type(Multiboxer_DataDB) ~= 'table' then
        Multiboxer_DataDB = {}
    end
    self.db = Multiboxer_DataDB

    self.charName = UnitName('player')
    self.realmName = GetRealmName()
    self.profileName = self.charName .. '-' .. self.realmName
    self.trackedItems = self.trackedItems or {}

    self.charDB = self.db[self.profileName] or {}
end