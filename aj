local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- Two different webhooks
local highWebhookURL = "https://discord.com/api/webhooks/1407314598520029204/BtGzGDMjk2f2TmxRdqQO71mgBpH7RI8mLTZkrlBYh7aIh43DvtZXH6gM3HwVNEQC5hLm"
local midWebhookURL  = "https://discord.com/api/webhooks/1407353026145947659/nhjJPETM_buCwGN-_6kmEso1oT83q_IlWbySuhweNzgaCWBTLnQqje7sKMad-il5IhIS"

local PLACE_ID = game.PlaceId
local currentJobId = game.JobId
local retryDelay = 1

local visitedServers = {}
local busy = false
local notified = {}

-- Custom emoji IDs
local emojis = {
    brainrot = "<:brainrot:1407320814549729443>",
    money    = "<:money:1407320808015003658>",
    players  = "<:players:1407320811295215678>",
    join     = "<:join:1407325742341029898>",
    phone    = "<:phone:868899810936229949>",
    script   = "<:script:1407320809395060776>"
}

local function parseValue(valueStr, multiplier)
    local num = tonumber(valueStr)
    if not num then return 0 end
    multiplier = multiplier:lower()
    if multiplier == "k" then return num * 1e3
    elseif multiplier == "m" then return num * 1e6
    elseif multiplier == "b" then return num * 1e9
    else return num end
end

local function sendDiscordWebhook(nameText, valueText, jobId, numericValue)
    local playersOnline = #Players:GetPlayers()
    local joinURL = string.format(
        "https://robloxfinderjoin.github.io/robloxfinder/?placeId=%d&gameInstanceId=%s",
        PLACE_ID,
        jobId
    )

    -- Pick webhook based on money/sec
    local webhookURL
    if numericValue >= 10e6 then -- 10m+
        webhookURL = highWebhookURL
    elseif numericValue >= 1e6 and numericValue < 10e6 then -- 1m–10m
        webhookURL = midWebhookURL
    else
        return -- ignore pets < 1m/s
    end

    local payload = HttpService:JSONEncode({
        content = "",
        embeds = {{
            title = "Aura Notifier",
            color = 0x000000,
            fields = {
                {name = emojis.brainrot.." Name", value = nameText, inline = false},
                {name = emojis.money.." Money/sec", value = valueText, inline = false},
                {name = emojis.players.." Players", value = tostring(playersOnline).."/8", inline = false},
                {name = emojis.join.." Auto Join", value = "[Click to join!]("..joinURL..")", inline = false},
                {name = emojis.phone.." Job ID (Mobile)", value = jobId, inline = false},
                {name = emojis.phone.." Job ID (PC)", value = jobId, inline = false},
                {name = emojis.script.." Script", value = "```game:GetService(\"TeleportService\"):TeleportToPlaceInstance("..PLACE_ID..",\""..jobId.."\",game.Players.LocalPlayer)```", inline = false}
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
        }}
    })

    local success, err = pcall(function()
        request({
            Url = webhookURL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = payload
        })
    end)

    if success then
        print("📨 Webhook sent for:", nameText, "at", valueText)
    else
        print("❌ Webhook error:", err)
    end
end

-- Scan EVERY pet instead of just the best one
local function scanAllBrainrots()
    if not workspace or not workspace.Plots then
        return {}
    end

    local foundPets = {}

    for _, plot in pairs(workspace.Plots:GetChildren()) do
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            for _, podium in pairs(podiums:GetChildren()) do
                local overhead = podium:FindFirstChild("Base")
                if overhead then
                    overhead = overhead:FindFirstChild("Spawn")
                    if overhead then
                        overhead = overhead:FindFirstChild("Attachment")
                        if overhead then
                            overhead = overhead:FindFirstChild("AnimalOverhead")
                            if overhead then
                                local brainrotData = {
                                    name = "Unknown",
                                    moneyPerSec = "$0/s",
                                    numericValue = 0
                                }

                                for _, label in pairs(overhead:GetChildren()) do
                                    if label:IsA("TextLabel") then
                                        local text = label.Text
                                        if text:find("/s") then
                                            brainrotData.moneyPerSec = text
                                        else
                                            brainrotData.name = text
                                        end
                                    end
                                end

                                local numericValue = parseValue(
                                    brainrotData.moneyPerSec:match("([%d%.]+)"),
                                    brainrotData.moneyPerSec:match("([KkMmBb])") or ""
                                )
                                brainrotData.numericValue = numericValue

                                if numericValue >= 1e6 then
                                    table.insert(foundPets, brainrotData)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return foundPets
end

local function hopServer()
    local maxTries = 2
    local tries = 0

    while tries < maxTries do
        tries = tries + 1
        local success, serverInfo = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..PLACE_ID.."/servers/Public?sortOrder=Asc&limit=100"))
        end)

        if success and serverInfo and serverInfo.data then
            local goodServers = {}
            for _, server in pairs(serverInfo.data) do
                if server.id and server.playing and server.playing < server.maxPlayers and server.playing >= 1 and not visitedServers[server.id] then
                    table.insert(goodServers, server)
                end
            end

            if #goodServers > 0 then
                local randomServer = goodServers[math.random(1, #goodServers)]
                visitedServers[randomServer.id] = true
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, randomServer.id, Players.LocalPlayer)
                end)
                return
            end
        end
        wait(0.001)
    end

    pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, "random", Players.LocalPlayer)
    end)
end

local function notifyBrainrots()
    if busy then return end
    busy = true

    local success, pets = pcall(scanAllBrainrots)

    if not success then
        print("Error scanning pets:", pets)
        hopServer()
        spawn(function() wait(0.5) busy = false end)
        return
    end

    if pets and #pets > 0 then
        local jobId = game.JobId or "Unknown"
        for _, pet in pairs(pets) do
            local brainrotKey = jobId.."_"..pet.name.."_"..pet.moneyPerSec
            if not notified[brainrotKey] then
                notified[brainrotKey] = true
                sendDiscordWebhook(pet.name, pet.moneyPerSec, jobId, pet.numericValue)
            end
        end
    end

    hopServer()
    spawn(function() wait(0.5) busy = false end)
end

local function retryLoop()
    while true do
        wait(0.1)
        local success, errorMsg = pcall(notifyBrainrots)
        if not success then
            print("Error in retryLoop:", errorMsg)
            wait(0.5)
        end
    end
end

spawn(retryLoop)
pcall(notifyBrainrots)
