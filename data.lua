local addonName, addonTable = ...

addonTable[1].itemIDs = {
    [168487] = true, -- zin'anthid
    [168185] = true, -- osmenite
    -- [2589] = true, -- DEBUG linen
    -- [124437] = true, -- shald silk
}

addonTable[1].professionData = {
    ['Herbalism'] = {
        skillLines = {
            main = 182, 
            expansion = 2549,
        },
        recipes = {
            ["Zin'anthid"] = 298144,
        },
    },
    ['Mining'] = {
        skillLines = {
            main = 186, 
            expansion = 2565,
        },
        recipes = {
            ['Osmenite Deposit'] = 296147, 
            ['Osmenite Seam'] = 296143,
        },
    },
}

addonTable[1].introQuestID = 55053