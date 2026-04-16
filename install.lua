local GITHUB_URL = "https://raw.githubusercontent.com/LeSpatiocorne/music_computercraft/main/music_direct.lua"
local PROGRAM_NAME = "music.lua"

term.clear()
term.setCursorPos(1,1)
print("==============================")
print(" Installing ZicParty...")
print("==============================")

local request = http.get(GITHUB_URL)
if not request then
    print("\n[Error] Unable to connect to GitHub.")
    print("Check that the HTTP API is enabled on the server.")
    return
end

local code = request.readAll()
request.close()

local file = fs.open(PROGRAM_NAME, "w")
file.write(code)
file.close()

print("\n[Success] Program installed as '" .. PROGRAM_NAME .. "' !")
print("\nLaunching automatically in 2 seconds...")
sleep(2)
term.clear()

shell.run(PROGRAM_NAME)
