local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
if not speaker then
    error("Aucun speaker trouve, connectez-en un!", 0)
end
local decoder = dfpwm.make_decoder()

local SERVER_URL = "https://cc-music.lespatioverse.xyz"
local WS_URL = "wss://cc-music.lespatioverse.xyz"

local ws = nil
local currentHttpHandle = nil
local abortedByCommand = false

local state = {
    code = nil,
    current = nil,
    next = nil,
    status = "idle",
    startTime = 0,
    serverTime = 0,
    pauseOffset = 0,
    localReceiveTime = 0,
    infoMsg = "Pret !",
    input = ""
}

local function forceBreakAudio()
    abortedByCommand = true
    if currentHttpHandle then
        pcall(function() currentHttpHandle.close() end)
        currentHttpHandle = nil
    end
end

local function draw()
    term.clear()
    term.setCursorPos(1, 1)
    print("=ZICPARTY=")
    if state.code then
        print("Code pour inviter et rejoindre : " .. state.code)
    else
        print("Rejoignez ou creez une salle (tapez create)")
    end
    print("")

    if state.current then
        print("En cours : " .. state.current.title .. " (" .. state.current.channel .. ")")
        if state.status == "playing" then
            if not state.current.ready then
                print("Statut   : Telechargement de la piste...")
            else
                print("Statut   : En lecture \14")
            end
        elseif state.status == "stopped" then
             print("Statut   : En pause ||")
        else
             print("Statut   : En attente...")
        end
    else
        print("En cours : Rien")
    end
    print("")

    if state.next then
        print("A suivre : " .. state.next.title)
    else
        print("A suivre : Rien")
    end
    print("")
    
    if state.infoMsg ~= "" then
        print("Infos    : " .. state.infoMsg)
    end

    local w, h = term.getSize()
    term.setCursorPos(1, h - 1)
    print("----------")
    term.setCursorPos(1, h)
    term.write("> " .. state.input)
end

local function handleCommand(cmd)
    local args = {}
    for word in cmd:gmatch("%S+") do table.insert(args, word) end
    if #args == 0 then return end
    
    local root = args[1]:lower()
    
    if root == "create" then
        ws.send(textutils.serializeJSON({type="create"}))
    elseif root == "join" and args[2] then
        ws.send(textutils.serializeJSON({type="join", code=args[2]}))
        forceBreakAudio()
    elseif root == "leave" then
        ws.send(textutils.serializeJSON({type="leave"}))
        state.code = nil
        state.current = nil
        state.next = nil
        forceBreakAudio()
        draw()
    elseif root == "sr" and args[2] then
        ws.send(textutils.serializeJSON({type="sr", url=args[2]}))
    elseif root == "sd" then
        ws.send(textutils.serializeJSON({type="sd"}))
        forceBreakAudio()
    elseif root == "next" then
        ws.send(textutils.serializeJSON({type="next"}))
        forceBreakAudio()
    elseif root == "prev" then
        ws.send(textutils.serializeJSON({type="prev"}))
        forceBreakAudio()
    elseif root == "pause" then
        ws.send(textutils.serializeJSON({type="pause"}))
        forceBreakAudio()
    elseif root == "play" then
        ws.send(textutils.serializeJSON({type="play"}))
    elseif root == "clear" then
        state.input = ""
        state.infoMsg = ""
        draw()
    elseif root == "help" then
        state.infoMsg = "create, join [code], leave, sr [url], sd, next, prev, pause, play, clear"
        draw()
    else
        state.infoMsg = "Commande inconnue. Tapez help."
        draw()
    end
end

local function inputLoop()
    while true do
        local event, key = os.pullEvent()
        if event == "char" then
            state.input = state.input .. key
            draw()
        elseif event == "paste" then
            state.input = state.input .. key
            draw()
        elseif event == "key" then
            if key == keys.backspace and #state.input > 0 then
                state.input = state.input:sub(1, -2)
                draw()
            elseif key == keys.enter then
                handleCommand(state.input)
                state.input = ""
                draw()
            end
        end
    end
end

local function wsLoop()
    while true do
        local msg = ws.receive()
        if msg then
            local data = textutils.unserializeJSON(msg)
            if data then
                if data.type == "joined" then
                    state.code = data.code
                    state.infoMsg = "Salon " .. state.code .. " rejoint!"
                    draw()
                elseif data.type == "info" then
                    state.infoMsg = data.message
                    draw()
                elseif data.type == "error" then
                    state.infoMsg = "Erreur: " .. data.message
                    draw()
                elseif data.type == "left" then
                    state.code = nil
                    state.infoMsg = "Vous avez quitte la salle."
                    draw()
                elseif data.type == "state" then
                    if data.code == state.code then
                        -- Check if status changed to stopped or track changed
                        if (state.status == "playing" and data.status ~= "playing") or 
                           (state.current and data.current and state.current.url ~= data.current.url) then
                            forceBreakAudio()
                        end
                        
                        state.current = data.current
                        state.next = data.next
                        state.status = data.status
                        state.startTime = data.startTime
                        state.pauseOffset = data.pauseOffset or 0
                        state.serverTime = data.serverTime
                        state.localReceiveTime = os.clock()
                        draw()
                    end
                end
            end
        else
            print("Deconnecte du serveur.")
            forceBreakAudio()
            break
        end
    end
end

local currentAudioId = nil

local function audioLoop()
    while true do
        sleep(0.1)
        if state.status == "playing" and state.current and state.current.ready and state.current.url then
            local targetUrl = state.current.url
            if targetUrl ~= currentAudioId then
                currentAudioId = targetUrl
                
                local serverDelta = (state.serverTime - state.startTime) / 1000
                local localDelta = os.clock() - state.localReceiveTime
                local elapsedSecs = serverDelta + localDelta
                
                if elapsedSecs < 0 then elapsedSecs = 0 end
                
                local offsetBytes = math.floor(elapsedSecs * 6000)
                
                local headers = {}
                if offsetBytes > 0 then
                    headers["Range"] = "bytes=" .. offsetBytes .. "-"
                end
                
                local reqUrl = SERVER_URL .. targetUrl
                local handle, err = http.get(reqUrl, headers, true)
                
                if handle then
                    currentHttpHandle = handle
                    while currentAudioId == targetUrl and state.status == "playing" and currentHttpHandle do
                        local ok, chunk = pcall(function() return currentHttpHandle.read(16 * 1024) end)
                        
                        if not ok or not chunk then break end
                        
                        local buffer = decoder(chunk)
                        while not speaker.playAudio(buffer) do
                            os.pullEvent("speaker_audio_empty")
                            if currentAudioId ~= targetUrl or state.status ~= "playing" or not currentHttpHandle then
                                break
                            end
                        end
                    end
                    if currentHttpHandle then
                        pcall(function() currentHttpHandle.close() end)
                        currentHttpHandle = nil
                    end
                end
                if currentAudioId == targetUrl and state.status == "playing" and not abortedByCommand then
                     ws.send(textutils.serializeJSON({type="next"}))
                end
                abortedByCommand = false
                currentAudioId = nil
            end
        else
            currentAudioId = nil
        end
    end
end

term.clear()
term.setCursorPos(1,1)
print("Connexion au serveur WebSockets...")
local err
ws, err = http.websocket(WS_URL)
if not ws then
    print("Erreur : connexion au serveur impossible (" .. tostring(err) .. ")")
    return
end

draw()

parallel.waitForAny(inputLoop, wsLoop, audioLoop)