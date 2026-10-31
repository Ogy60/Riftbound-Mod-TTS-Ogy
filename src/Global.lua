--[[
  RIFTBOUND MOD TTS OGY  -  Riftbound TCG table for Tabletop Simulator    v1.0
  =====================================================================
  Modes      1v1, 2v2 (teams, shared points), FFA 3, FFA 4 - every player
             gets their own table side in the multiplayer modes
  Controls   In-world: each seat has a control strip on the table (sit,
             deck code, import, draw, channel, phases, score, XP); the
             host has a table console. TTS's own turn system shows whose
             turn it is. No screen overlay.
  Importer   Piltover Archive deck codes (format v1-v6), Piltover TTS
             export strings, or plain lists ("3 OGN-007")
  Game flow  Random first player, battlefields per mode, opening hand of
             4, mulligan (up to 2, recycled to the bottom), turn phases
             (Awaken / Beginning / Channel / Draw / Main / End), first-turn
             adjustments, Burn Out, end-of-turn healing
  Extras     Dice per seat, token trays, card right-click actions

  Card data and images: Riot's official card gallery (playriftbound.com),
  with the open Riftcodex API (https://api.riftcodex.com) as fallback,
  loaded when a deck is imported. Nothing card-related ships in the save.

  Deck-code decoding is a Lua port of Piltover Archive's
  RiftboundDeckCodes (Apache-2.0):
  https://github.com/Piltover-Archive/RiftboundDeckCodes

  Riftbound Mod TTS Ogy was created under Riot Games' "Legal Jibber Jabber"
  policy using assets owned by Riot Games. Riot Games does not endorse or
  sponsor this project.
]]

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------

MOD_NAME    = "Riftbound Mod TTS Ogy"
MOD_VERSION = "1.0"
REPO_URL    = "https://github.com/Ogy60/Riftbound-Mod-TTS-Ogy"
ISSUES_URL  = REPO_URL .. "/issues"
DISCLAIMER  = MOD_NAME .. " was created under Riot Games' \"Legal Jibber Jabber\" policy using " ..
              "assets owned by Riot Games. Riot Games does not endorse or sponsor this project."

-- Optional hard-coded asset URLs (the host can also set them in-game).
DEFAULT_BACK_URL = ""
DEFAULT_MAT_URL  = ""
DEFAULT_BF_URL   = ""

API_BASE   = "https://api.riftcodex.com"
CARD_SCALE = 1.2

-- In-world controls: TTS button units per world unit, and an extra
-- rotation in case labels read upside down on your TTS version.
BTN_UNITS      = 450
BTN_ROT_OFFSET = 180

MODES = {
  Duel = { label = "1v1",   seats = { "Red", "Blue" },                     victory = 8,
           battlefields = 2, firstGivesBF = true },
  Team = { label = "2v2",   seats = { "Red", "Blue", "Yellow", "Green" },  victory = 11,
           battlefields = 3, firstGivesBF = false,
           teams = { A = { "Red", "Yellow" }, B = { "Blue", "Green" } } },
  FFA3 = { label = "FFA 3", seats = { "Red", "Blue", "Green" },            victory = 8,
           battlefields = 3, firstGivesBF = true },
  FFA4 = { label = "FFA 4", seats = { "Red", "Blue", "Yellow", "Green" },  victory = 8,
           battlefields = 3, firstGivesBF = false },
}
MODE_ORDER = { "Duel", "Team", "FFA3", "FFA4" }

-- Clockwise seen from above: south, west, north, east.
-- 2v2 partners sit opposite each other, so turns alternate teams.
CYCLES = {
  Duel = { "Red", "Blue" },
  Team = { "Red", "Blue", "Yellow", "Green" },
  FFA3 = { "Red", "Blue", "Green" },
  FFA4 = { "Red", "Blue", "Yellow", "Green" },
}

PHASES = { "Awaken", "Beginning", "Channel", "Draw", "Main", "End" }
PHASE_HINT = {
  Awaken    = "Ready all your cards.",
  Beginning = "Start-of-turn effects, then score a point for each battlefield you hold.",
  Channel   = "Channel 2 runes.",
  Draw      = "Draw 1 card.",
  Main      = "Play cards, move units, fight. End your turn when done.",
  End       = "End-of-turn effects. All units heal.",
}

COLOR_RGB = {
  Red    = { 0.86, 0.26, 0.24 }, Blue  = { 0.27, 0.53, 0.92 },
  Green  = { 0.30, 0.72, 0.38 }, Yellow = { 0.93, 0.78, 0.25 },
}
COLOR_HEX = { Red = "#DB4A3D", Blue = "#4A88EB", Green = "#4DB861", Yellow = "#EDC740" }
GOLD = { 0.80, 0.63, 0.30 }

------------------------------------------------------------------------
-- STATE (persisted)
------------------------------------------------------------------------

state = {
  version      = 2,
  mode         = "Duel",
  back         = "",
  mat          = "",
  bfMat        = "",
  markers      = "",
  matFlip      = false,
  autoPhases   = true,
  nextDeckId   = 0,
  points       = {},
  xp           = {},
  game         = nil,
  boardVersion = 0,
  hands        = { Red = "a1b2c3", Blue = "d4e5f6", Yellow = "b7c8d9", Green = "e1f2a3" },
}

inputs        = {}
importing     = {}
cardCache     = {}
menuAdded     = {}
ctl           = {}
surfaceY      = 1.3
boardBuilding = false

------------------------------------------------------------------------
-- GEOMETRY
-- Every seat has a local frame: u to the player's right, z toward the
-- table centre. Zones are given in mat coordinates (u, v), v toward the
-- centre, with the mat centred at local z = matZ.
------------------------------------------------------------------------

function mode() return MODES[state.mode] end

function isSeat(color)
  for _, c in ipairs(mode().seats) do if c == color then return true end end
  return false
end

SIDES = {
  S = { r = { 1, 0 },  f = { 0, 1 },  cardRot = 180 },
  N = { r = { -1, 0 }, f = { 0, -1 }, cardRot = 0 },
  W = { r = { 0, -1 }, f = { 1, 0 },  cardRot = 270 },
  E = { r = { 0, 1 },  f = { -1, 0 }, cardRot = 90 },
}
SEAT_SIDE = {
  Duel = { Red = "S", Blue = "N" },
  Four = { Red = "S", Blue = "W", Yellow = "N", Green = "E" },
}

LAYOUT = {
  Duel = { tableW = 76, tableD = 58, matZ = -16, consoleZ = -26.7, handZ = -33.5 },
  Four = { tableW = 90, tableD = 90, matZ = -32, consoleZ = -42.7, handZ = -50.5 },
}

function layoutKey() return (state.mode == "Duel") and "Duel" or "Four" end
function layout() return LAYOUT[layoutKey()] end

function seatFrame(color)
  if not isSeat(color) then return nil end
  local side = SEAT_SIDE[layoutKey()][color]
  local s, L = SIDES[side], layout()
  return {
    side = side, r = s.r, f = s.f,
    cardRotY = s.cardRot, textRotY = (s.cardRot + 180) % 360,
    matZ = L.matZ, consoleZ = L.consoleZ, handZ = L.handZ,
  }
end

function localToWorld(f, u, z)
  return f.r[1] * u + f.f[1] * z, f.r[2] * u + f.f[2] * z
end

-- (u, v) in mat coordinates -> world position {x, y, z}
function toWorld(color, u, v, dy)
  local f = seatFrame(color)
  local x, z = localToWorld(f, u, f.matZ + v)
  return { x, surfaceY + (dy or 0.6), z }
end

-- (u, dz) relative to the seat's control strip -> world {x, z}
function consoleXZ(color, u, dz)
  local f = seatFrame(color)
  return localToWorld(f, u, f.consoleZ + (dz or 0))
end

function zonePos(color, zone, dy)
  local z = ZONES[zone]
  return toWorld(color, z[1], z[2], dy)
end

MAT_W, MAT_D = 46, 17

-- name = { u, v, label, landscape }
ZONES = {
  legend    = { -19.5,  4.4, "LEGEND" },
  champion  = { -15.5,  4.4, "CHAMPION" },
  mainDeck  = {  12.6,  4.4, "MAIN DECK" },
  trash     = {  16.6,  4.4, "TRASH" },
  banish    = {  20.6,  4.4, "BANISHED" },
  runeDeck  = { -19.5, -4.2, "RUNE DECK" },
  bfPick    = {  16.6, -4.2, "BATTLEFIELDS", true },
  sideboard = {  20.6, -4.2, "SIDEBOARD" },
  dice      = {  20.6,  0.1, "DICE" },
}
BASE_AREA   = { x1 = -13.0, x2 =  4.4, z1 =  1.6, z2 =  7.6, label = "BASE" }
REVEAL_AREA = { x1 =   5.0, x2 = 10.4, z1 =  1.6, z2 =  7.6, label = "REVEAL" }
POOL_AREA  = { x1 = -17.4, x2 = 13.9, z1 = -7.6, z2 = -1.4, label = "RUNE POOL" }
POOL_SLOTS = { x0 = -15.95, dx = 2.58, z = -4.5, count = 12 }

-- Drop areas shown while dragging a card (mat coordinates): the deck spot
-- itself is "top", the area just below it is "bottom".
DROP_BOTTOM = { mainDeck = { 12.6, 0.1 }, runeDeck = { -19.5, 0.1 } }
DROP_W, DROP_H = 2.9, 1.5

-- Temporary action bar after Peek / Reveal (mat gap row)
ACTION_ROW_V = 0.1

-- Private peek area: a second hand zone next to the player's hand
PEEK_U, PEEK_W = 15.5, 12
SEAT_RECT  = { x1 = -23, x2 = 23, z1 = -8.5, z2 = 8.5 }

CARD_W, CARD_H = 2.6, 3.7

function bfSlots()
  if state.mode == "Duel" then return { -9, 9 } end
  return { -14, 0, 14 }
end

function matSize()
  local L = layout()
  return L.tableW, L.tableD
end

BOARD_VERSION = 9

------------------------------------------------------------------------
-- DECK CODE DECODER  (port of RiftboundDeckCodes; verified against the
-- library's golden fixtures for versions 1-6)
------------------------------------------------------------------------

B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
SET_IDS     = { [0]="OGN", [1]="OGS", [2]="ARC", [3]="SFD", [4]="UNL", [5]="VEN", [6]="RAD" }
VARIANT_IDS = { [0]="", [1]="a", [2]="s", [3]="b" }

function base32Decode(s)
  local out, buf, bits = {}, 0, 0
  for i = 1, #s do
    local ch = s:sub(i, i)
    if not ch:match("[%s=]") then
      local v = B32:find(ch:upper(), 1, true)
      if not v then error("Invalid character in deck code: '" .. ch .. "'") end
      buf = buf * 32 + (v - 1)
      bits = bits + 5
      if bits >= 8 then
        bits = bits - 8
        local p = 2 ^ bits
        out[#out + 1] = math.floor(buf / p) % 256
        buf = buf % p
      end
    end
  end
  return out
end

function newReader(bytes)
  local r = { b = bytes, i = 1 }
  function r.byte()
    local v = r.b[r.i]
    if v == nil then error("Deck code ended unexpectedly") end
    r.i = r.i + 1
    return v
  end
  function r.var()
    local res, mul = 0, 1
    while true do
      local v = r.byte()
      res = res + (v % 128) * mul
      if v < 128 then return res end
      mul = mul * 128
    end
  end
  return r
end

function pad(n, w)
  local s = tostring(math.floor(n))
  while #s < w do s = "0" .. s end
  return s
end

function readNumber(r, flagged)
  if not flagged then return pad(r.var(), 3) end
  local f = r.byte()
  local n = r.var()
  if f == 0 then return pad(n, 3) end
  if f == 1 then return "R" .. pad(n, 2) end
  if f == 2 then return "SP" .. tostring(math.floor(n)) end
  error("Unknown number-prefix flag: " .. f)
end

function setName(id)
  local s = SET_IDS[id]
  if not s then error("Unknown set id " .. id .. " (deck code is newer than this mod)") end
  return s
end

function variantName(id)
  local v = VARIANT_IDS[id]
  if v == nil then error("Unknown variant id " .. id) end
  return v
end

function readGroup(r, count, flagged, deck)
  local n = r.var()
  local setCode = setName(r.byte())
  local variant = variantName(r.byte())
  for _ = 1, n do
    deck[#deck + 1] = { code = setCode .. "-" .. readNumber(r, flagged) .. variant, count = count }
  end
end

function readSectionFixed(r, maxCount, flagged)
  local deck = {}
  for c = maxCount, 1, -1 do
    local groups = r.var()
    for _ = 1, groups do readGroup(r, c, flagged, deck) end
  end
  return deck
end

function readSectionSparse(r, flagged)
  local deck = {}
  local counts = r.var()
  for _ = 1, counts do
    local c = r.var()
    local groups = r.var()
    for _ = 1, groups do readGroup(r, c, flagged, deck) end
  end
  return deck
end

function readCardRef(r, flagged)
  local setCode = setName(r.byte())
  local variant = variantName(r.byte())
  return setCode .. "-" .. readNumber(r, flagged) .. variant
end

function decodeDeckCode(code)
  local r = newReader(base32Decode(code))
  local fv = r.byte()
  local format, version = math.floor(fv / 16), fv % 16
  if format ~= 1 then error("Not a Riftbound deck code (format " .. format .. ")") end
  if version < 1 or version > 6 then error("Unsupported deck code version " .. version) end

  local flagged, main, side
  if version >= 5 then
    local pf = r.byte()
    if pf > 1 then error("Unsupported deck prefix flag " .. pf) end
    flagged = (pf == 1)
    main = readSectionSparse(r, flagged)
    side = readSectionSparse(r, flagged)
  else
    flagged = version >= 4
    main = readSectionFixed(r, 12, flagged)
    side = (version >= 2) and readSectionFixed(r, 3, flagged) or {}
  end

  local result = { main = main, side = side, champion = nil, legends = {} }
  if version >= 3 and r.byte() == 1 then
    result.champion = readCardRef(r, flagged)
  end
  if version >= 6 then
    local n = r.var()
    for _ = 1, n do result.legends[#result.legends + 1] = readCardRef(r, flagged) end
  end
  return result
end

------------------------------------------------------------------------
-- CARD CODES
------------------------------------------------------------------------

function parseCode(code)
  if type(code) ~= "string" then return nil end
  local set, rest = code:match("^%s*(%a%a%a)%-([%w%*]+)%s*$")
  if not set then return nil end
  local prefix, digits, variant = rest:match("^(%a*)(%d+)([%a%*]?)$")
  if not digits then return nil end
  prefix = prefix:upper()
  if prefix ~= "" and prefix ~= "R" and prefix ~= "SP" then return nil end
  variant = variant:lower()
  if variant == "*" then variant = "s" end
  return { set = set:upper(), prefix = prefix, num = tonumber(digits), digits = digits, variant = variant }
end

function canonKey(p, withVariant)
  local k = p.set:lower() .. "-" .. p.prefix:lower() .. tostring(p.num)
  if withVariant then k = k .. p.variant end
  return k
end

function keyFromRiftcodexId(id)
  if type(id) ~= "string" then return nil end
  local set, rest = id:match("^(%a+)%-([%w%*]+)")
  if not set or #set ~= 3 then return nil end
  local p = parseCode(set .. "-" .. rest)
  if not p then return nil end
  return canonKey(p, true)
end

function lookupQuery(p)
  local num
  if p.prefix == "R" then num = "r" .. pad(p.num, 2)
  elseif p.prefix == "SP" then num = "sp" .. p.digits
  else num = pad(p.num, 3) end
  return p.set:lower() .. "-" .. num
end

function normCode(code)
  local p = parseCode(code)
  if not p then return nil end
  return p.set .. "-" .. code:match("%-([%w%*]+)%s*$")
end

------------------------------------------------------------------------
-- INPUT PARSING
------------------------------------------------------------------------

function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function addCount(list, code, n)
  for _, e in ipairs(list) do
    if e.code == code then e.count = e.count + n; return end
  end
  list[#list + 1] = { code = code, count = n }
end

function parseInput(text)
  text = trim(text)
  if text == "" then error("Paste a deck code first.") end
  if text:find("piltoverarchive%.com") then
    error("That's a deck link. On Piltover Archive open the deck, choose Export, copy the deck code and paste it here.")
  end

  local compact = text:gsub("%s", "")
  if #compact >= 12 and compact:match("^[A-Za-z2-7=]+$") then
    return decodeDeckCode(compact), "deck code"
  end

  local result = { main = {}, side = {}, champion = nil, legends = {} }
  local target = result.main
  local found = 0
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local l = trim(line)
    local lower = l:lower()
    if lower:match("^side") then
      target = result.side
    elseif lower:match("^main") or lower:match("^deck") then
      target = result.main
    elseif l ~= "" then
      local n, code = l:match("^(%d+)%s*[xX]?%s+(%a%a%a%-[%w%*]+)")
      if not n then code, n = l:match("^(%a%a%a%-[%w%*]+)%s+[xX]?(%d+)$") end
      if n and normCode(code) then
        addCount(target, normCode(code), tonumber(n))
        found = found + 1
      else
        for tok in l:gmatch("%f[%w](%a%a%a%-[%w%*]+)") do
          if normCode(tok) then
            addCount(target, normCode(tok), 1)
            found = found + 1
          end
        end
      end
    end
  end
  if found == 0 then
    error("Couldn't read that. Paste a Piltover Archive deck code, a TTS export, or lines like '3 OGN-007'.")
  end
  return result, "card list"
end

------------------------------------------------------------------------
-- CARD LOOKUP (Riftcodex)
------------------------------------------------------------------------

function cardInfoFromItem(item, code)
  local cls   = item.classification or {}
  local attrs = item.attributes or {}
  local media = item.media or {}
  local txt   = item.text or {}

  local desc = {}
  local typeLine = (type(cls.supertype) == "string" and (cls.supertype .. " ") or "") .. tostring(cls.type or "")
  if type(cls.domain) == "table" and #cls.domain > 0 then
    typeLine = typeLine .. "  -  " .. table.concat(cls.domain, " / ")
  end
  desc[#desc + 1] = typeLine
  local stats = {}
  if attrs.energy ~= nil then stats[#stats + 1] = "Energy " .. tostring(attrs.energy) end
  if attrs.power  ~= nil then stats[#stats + 1] = "Power "  .. tostring(attrs.power)  end
  if attrs.might  ~= nil then stats[#stats + 1] = "Might "  .. tostring(attrs.might)  end
  if #stats > 0 then desc[#desc + 1] = table.concat(stats, "  |  ") end
  if type(txt.plain) == "string" and txt.plain ~= "" then desc[#desc + 1] = "\n" .. txt.plain end
  desc[#desc + 1] = "\n[" .. code .. "]"

  return {
    code      = code,
    name      = item.name or code,
    type      = tostring(cls.type or "Unknown"),
    supertype = cls.supertype,
    tags      = type(item.tags) == "table" and item.tags or {},
    image     = media.image_url,
    landscape = (item.orientation == "landscape"),
    desc      = table.concat(desc, "\n"),
    rules     = (type(txt.plain) == "string") and txt.plain or "",
  }
end

function placeholderInfo(code, name)
  return {
    code = code, name = name or (code .. " (not found)"), type = "Unknown", tags = {},
    image = nil, landscape = false,
    desc = "No card data found for " .. code .. ".",
  }
end

function httpJSON(url, cb)
  WebRequest.get(url, function(req)
    local code = req.response_code
    if req.is_error or (code and code >= 400) then
      cb(nil, "HTTP " .. tostring(code or "?") .. " " .. tostring(req.error or ""))
      return
    end
    local ok, data = pcall(JSON.decode, req.text)
    if ok and type(data) == "table" then cb(data)
    else cb(nil, "unreadable response: " .. tostring(req.text):sub(1, 80)) end
  end)
end


------------------------------------------------------------------------
-- OFFICIAL CARD DATA (Riot's card gallery, all sets incl. the newest)
-- The gallery page embeds every card as JSON. It is downloaded once per
-- session; only the cards in a deck are read out of it.
------------------------------------------------------------------------

OFFICIAL_URL = "https://playriftbound.com/en-us/card-gallery/"
official = nil          -- { text = string, index = { canonKey = {s, e} } }
officialWaiting = nil
officialError = nil

TYPE_LABEL  = { unit = "Unit", spell = "Spell", battlefield = "Battlefield", legend = "Legend", gear = "Gear", rune = "Rune" }
SUPER_LABEL = { champion = "Champion", signature = "Signature", token = "Token", basic = "Basic" }

function utf8char(n)
  if n < 128 then return string.char(n) end
  if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
  return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
end

function jsonUnescape(v)
  if not v then return nil end
  v = v:gsub("\\u(%x%x%x%x)", function(h) return utf8char(tonumber(h, 16)) end)
  v = v:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\n", " "):gsub("\\\\", "\\")
  return v
end

-- "rad-025-167" -> key, "unl-230-star-219" -> signed, "rad-r04a" -> rune alt
function officialKey(id)
  local set, rest, tail = id:match("^(%a%a%a)%-(%w+)(.*)$")
  if not set then return nil end
  local star = tail:find("star", 1, true) ~= nil
  local p = parseCode(set .. "-" .. rest .. (star and "s" or ""))
  return p and canonKey(p, true)
end

function loadOfficial(cb)
  if official then cb(official); return end
  if officialError then cb(nil, officialError); return end
  if officialWaiting then table.insert(officialWaiting, cb); return end
  officialWaiting = { cb }
  WebRequest.get(OFFICIAL_URL, function(req)
    local ok, err = pcall(function()
      if req.is_error then error(tostring(req.error)) end
      local text = req.text or ""
      local a = text:find('__NEXT_DATA__', 1, true)
      if not a then error("card data not found on the gallery page") end
      local index, starts, pos = {}, {}, a
      while true do
        local s1, e1, id = text:find('{"id":"(%a%a%a%-%a?%a?%d[%w%-]*)"', pos)
        if not s1 then break end
        starts[#starts + 1] = { s1, id }
        pos = e1 + 1
      end
      local tokens = {}
      for i, st in ipairs(starts) do
        local nxt = starts[i + 1]
        local range = { st[1], nxt and (nxt[1] - 1) or math.min(#text, st[1] + 8000) }
        if st[2]:find("^%a%a%a%-t%d") then tokens[#tokens + 1] = range end
        local key = officialKey(st[2])
        if key and not index[key] then
          local nxt = starts[i + 1]
          index[key] = { st[1], nxt and (nxt[1] - 1) or math.min(#text, st[1] + 8000) }
        end
      end
      local n = 0
      for _ in pairs(index) do n = n + 1 end
      if n < 100 then error("only " .. n .. " cards found on the gallery page") end
      -- token cards with normal numbers carry a "token" super type
      local p2 = a
      while true do
        local t1 = text:find('"id":"token"', p2, true)
        if not t1 then break end
        local lo, hi = 1, #starts
        while lo < hi do
          local mid = math.floor((lo + hi + 1) / 2)
          if starts[mid][1] <= t1 then lo = mid else hi = mid - 1 end
        end
        local st = starts[lo]
        if st and not st[2]:find("^%a%a%a%-t%d") then
          local nxt = starts[lo + 1]
          tokens[#tokens + 1] = { st[1], nxt and (nxt[1] - 1) or math.min(#text, st[1] + 8000) }
        end
        p2 = t1 + 10
      end
      official = { text = text, index = index, count = n, tokens = tokens }
    end)
    if not ok then officialError = tostring(err):gsub("^.-:%d+: ", "") end
    local waiting = officialWaiting
    officialWaiting = nil
    for _, f in ipairs(waiting) do
      if official then f(official) else f(nil, officialError) end
    end
  end)
end

-- Reads the JSON string value that follows `key` after the first `anchor`
-- (handles escaped quotes; no fragile key-order assumptions)
function jsonString(seg, anchor, key)
  local a = seg:find(anchor, 1, true)
  if not a then return nil end
  local k = seg:find(key, a, true)
  if not k or k - a > 6000 then return nil end
  local i = k + #key
  local j = i
  while true do
    local q = seg:find('"', j, true)
    if not q then return nil end
    local bs, p = 0, q - 1
    while p >= i and seg:sub(p, p) == "\\" do bs = bs + 1; p = p - 1 end
    if bs % 2 == 0 then return seg:sub(i, q - 1) end
    j = q + 1
  end
end

-- Builds the same item shape the Riftcodex reader understands
function officialItem(key)
  local r = official and official.index[key]
  if not r then return nil end
  return officialItemRange(r)
end

function officialItemRange(r)
  local seg = official.text:sub(r[1], r[2])
  local function field(name) return jsonUnescape(seg:match('"' .. name .. '":"([^"]*)"')) end
  local function stat(name)
    local v = seg:match('"' .. name .. '":{"label":"[^"]*","value":{"id":(%-?%d+)')
    return v and tonumber(v) or nil
  end

  local typ, super = nil, nil
  local a = seg:find('"cardType":', 1, true)
  if a then
    local b = seg:find('"publicCode"', a, true) or (a + 3000)
    local ct = seg:sub(a, b)
    for id in ct:gmatch('"id":"(%a+)","label"') do
      if TYPE_LABEL[id] and not typ then typ = TYPE_LABEL[id] end
      if SUPER_LABEL[id] and not super then super = SUPER_LABEL[id] end
    end
  end

  -- The image description ("Riftbound Unit: ...") is the most reliable type
  -- source; the type field is empty or wrong on a few cards.
  local acc = seg:match('"accessibilityText":"Riftbound ([%a ]*):')
  if acc then
    for word in acc:gmatch("%a+") do
      local w = word:lower()
      if TYPE_LABEL[w] then typ = TYPE_LABEL[w] end
      if SUPER_LABEL[w] then super = super or SUPER_LABEL[w] end
    end
  end

  local image
  local ci = seg:find('"cardImage":', 1, true)
  if ci then image = jsonUnescape(seg:match('"url":"([^"]*)"', ci)) end

  local tags = {}
  local tl = seg:match('"tags":{"label":"[^"]*","tags":%[([^%]]*)%]')
  if tl then for t in tl:gmatch('"([^"]*)"') do tags[#tags + 1] = jsonUnescape(t) end end

  local domains = {}
  local d1 = seg:find('"domain":', 1, true)
  if d1 then
    local d2 = seg:find('"cardImage"', d1, true) or (d1 + 3000)
    for _, lbl in seg:sub(d1, d2):gmatch('"id":"(%a+)","label":"(%a+)"') do domains[#domains + 1] = lbl end
  end

  local body = jsonString(seg, '"richText":', '"body":"')
  if not body or body == "" then
    -- image description: "Riftbound <Type>: <Name>. <rules text>"
    local acc = jsonString(seg, '"cardImage":', '"accessibilityText":"')
    if acc then
      local nm = field("name") or ""
      local i = acc:find(nm .. ".", 1, true)
      if i then body = acc:sub(i + #nm + 1):gsub("^%s+", "") end
    end
  end
  local plain = body and jsonUnescape(body):gsub("<br%s*/?>", "\n"):gsub("</p>", "\n"):gsub("<[^>]+>", "") or nil

  return {
    name = field("name"),
    riftbound_id = seg:match('^{"id":"([^"]*)"'),
    classification = { type = typ or "Unknown", supertype = super, domain = domains },
    attributes = { energy = stat("energy"), might = stat("might"), power = stat("power") },
    text = { plain = plain },
    media = { image_url = image },
    orientation = seg:match('"orientation":"(%a+)"') or "portrait",
    tags = tags,
  }
end

-- Official data first; anything it can't resolve falls back to Riftcodex
function fetchCards(codes, callback)
  loadOfficial(function(off, err)
    local info, warnings, rest = {}, {}, {}
    if not off then
      warnings[#warnings + 1] = "Official card gallery unavailable (" .. tostring(err) .. "), using Riftcodex"
    end
    for _, code in ipairs(codes) do
      local p = parseCode(code)
      local function read(key)
        local ok, it = pcall(officialItem, key)
        if ok then return it end
        warnings[#warnings + 1] = code .. ": could not read official data (" .. tostring(it):gsub("^.-:%d+: ", "") .. ")"
        return nil
      end
      local item = off and p and read(canonKey(p, true)) or nil
      local usedBase = false
      if off and p and not item then
        item = read(canonKey(p, false))
        usedBase = item ~= nil
      end
      if item and item.media.image_url then
        info[code] = cardInfoFromItem(item, code)
        if usedBase then warnings[#warnings + 1] = code .. ": that printing isn't listed, used the base art" end
      else
        rest[#rest + 1] = code
      end
    end
    if #rest == 0 then callback(info, warnings); return end
    fetchCardsRiftcodex(rest, function(info2, warnings2)
      for k, v in pairs(info2) do info[k] = v end
      for _, w in ipairs(warnings2) do warnings[#warnings + 1] = w end
      callback(info, warnings)
    end)
  end)
end

function fetchCardsRiftcodex(codes, callback)
  local byQuery, queries = {}, {}
  for _, code in ipairs(codes) do
    local p = parseCode(code)
    if p then
      local q = lookupQuery(p)
      if not byQuery[q] then byQuery[q] = {}; queries[#queries + 1] = q end
      table.insert(byQuery[q], code)
    end
  end

  local pending, done, warnings, info = #queries, false, {}, {}

  local function resolve(q, items)
    for _, code in ipairs(byQuery[q]) do
      local p = parseCode(code)
      local want, wantBase = canonKey(p, true), canonKey(p, false)
      local exact, base
      for _, item in ipairs(items or {}) do
        local k = keyFromRiftcodexId(item.riftbound_id)
        if k == want and not exact then exact = item end
        if k == wantBase and not base then base = item end
      end
      if exact then
        info[code] = cardInfoFromItem(exact, code)
      elseif base then
        info[code] = cardInfoFromItem(base, code)
        warnings[#warnings + 1] = code .. ": that printing isn't in the database, used the base art"
      else
        info[code] = placeholderInfo(code)
        warnings[#warnings + 1] = code .. ": not found"
      end
    end
  end

  local function finish()
    if done then return end
    done = true
    callback(info, warnings)
  end

  if pending == 0 then finish(); return end

  for _, q in ipairs(queries) do
    if cardCache[q] then
      resolve(q, cardCache[q])
      pending = pending - 1
      if pending == 0 then finish() end
    else
      httpJSON(API_BASE .. "/cards/riftbound/" .. q, function(data, err)
        local items = {}
        if data then
          items = data.items or data
          cardCache[q] = items
        else
          warnings[#warnings + 1] = q .. ": lookup failed (" .. tostring(err) .. ")"
        end
        resolve(q, items)
        pending = pending - 1
        if pending == 0 then finish() end
      end)
    end
  end

  Wait.time(function()
    if not done then
      for _, q in ipairs(queries) do
        for _, code in ipairs(byQuery[q]) do
          if not info[code] then info[code] = placeholderInfo(code) end
        end
      end
      warnings[#warnings + 1] = "Some lookups timed out (is api.riftcodex.com reachable?)"
      finish()
    end
  end, 30)
end

------------------------------------------------------------------------
-- SPAWNING CARDS
------------------------------------------------------------------------

function backURL()
  if state.back ~= "" then return state.back end
  return DEFAULT_BACK_URL
end

function matURL()
  if state.mat ~= "" then return state.mat end
  return DEFAULT_MAT_URL
end

function bfURL()
  if (state.bfMat or "") ~= "" then return state.bfMat end
  return DEFAULT_BF_URL
end

function nextDeckId()
  if state.nextDeckId < 1000 then state.nextDeckId = math.random(1000, 4000) end
  state.nextDeckId = state.nextDeckId + 1
  if state.nextDeckId > 9900 then state.nextDeckId = 1001 end
  return state.nextDeckId
end

function cardData(info, color)
  local id = nextDeckId()
  local face = info.image or backURL()
  return {
    Name = "Card",
    Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0,
                  scaleX = CARD_SCALE, scaleY = 1, scaleZ = CARD_SCALE },
    Nickname = info.name,
    Description = info.desc,
    GMNotes = info.code,
    Memo = info.rules or "",
    CardID = id * 100,
    SidewaysCard = info.landscape,
    Hands = true,
    Tags = { "Riftbound", "RB_" .. color, "RB_" .. info.type, info.extraTag },
    CustomDeck = {
      [tostring(id)] = {
        FaceURL = face, BackURL = backURL(),
        NumWidth = 1, NumHeight = 1, BackIsHidden = true, UniqueBack = false, Type = 0,
      },
    },
  }, id
end

function shuffleList(t)
  for i = #t, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

function deckDataFromCards(cardDatas, color, name, sideways)
  local data = {
    Name = "Deck", Nickname = name or "",
    Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0,
                  scaleX = CARD_SCALE, scaleY = 1, scaleZ = CARD_SCALE },
    DeckIDs = {}, CustomDeck = {}, ContainedObjects = {},
    Hands = false, SidewaysCard = sideways or false,
    Tags = { "Riftbound", "RB_" .. color },
  }
  for _, c in ipairs(cardDatas) do
    table.insert(data.DeckIDs, c.CardID)
    for k, v in pairs(c.CustomDeck or {}) do data.CustomDeck[tostring(k)] = v end
    table.insert(data.ContainedObjects, c)
  end
  return data
end

function spawnPile(color, infos, pos, faceUp, name, onDone)
  if #infos == 0 then return end
  local rot = { 0, seatFrame(color).cardRotY, faceUp and 0 or 180 }
  local data
  if #infos == 1 then
    data = cardData(infos[1], color)
  else
    local cds = {}
    for _, info in ipairs(infos) do cds[#cds + 1] = (cardData(info, color)) end
    data = deckDataFromCards(cds, color, name, infos[1].landscape)
  end
  data.Transform.posX, data.Transform.posY, data.Transform.posZ = pos[1], pos[2], pos[3]
  data.Transform.rotX, data.Transform.rotY, data.Transform.rotZ = rot[1], rot[2], rot[3]
  spawnObjectData({
    data = data, position = pos, rotation = rot,
    callback_function = function(obj)
      obj.setPosition(pos)
      obj.setRotation(rot)
      if name and name ~= "" then obj.setName(name) end
      if onDone then onDone(obj) end
    end,
  })
end

------------------------------------------------------------------------
-- IMPORT
------------------------------------------------------------------------

function buildDeck(color, deck, info, warnings, sourceLabel)
  clearArea(color)

  local legends, battlefields, runes, main, side, tokens = {}, {}, {}, {}, {}, {}
  local unknownTypes = 0

  -- Card type decides the place. If the lookup failed (type unknown), runes
  -- are still recognised by their R-number or by having more than 3 copies.
  local function kindOf(ci, code, count)
    local t = ci.type
    if t == "Legend" or t == "Battlefield" or t == "Rune" then return t end
    local sup = tostring(ci.supertype or ""):lower()
    if t == "Token" or sup:find("token") then return "Token" end
    if t == "Unknown" then
      unknownTypes = unknownTypes + 1
      local p = parseCode(code)
      if (p and p.prefix == "R") or count > 3 then return "Rune" end
    end
    return "Main"
  end

  for _, e in ipairs(deck.main) do
    local ci = info[e.code] or placeholderInfo(e.code)
    local k = kindOf(ci, e.code, e.count)
    for _ = 1, e.count do
      if k == "Legend" then table.insert(legends, ci)
      elseif k == "Battlefield" then table.insert(battlefields, ci)
      elseif k == "Rune" then table.insert(runes, ci)
      elseif k == "Token" then table.insert(tokens, ci)
      else table.insert(main, ci) end
    end
  end
  for _, code in ipairs(deck.legends or {}) do
    table.insert(legends, info[code] or placeholderInfo(code))
  end
  for _, e in ipairs(deck.side) do
    local ci = info[e.code] or placeholderInfo(e.code)
    for _ = 1, e.count do table.insert(side, ci) end
  end

  -- Champion candidates: every copy of a Champion unit that belongs to the
  -- Legend (same champion tag), or the chosen champion from the deck code.
  local tagSet = {}
  for _, l in ipairs(legends) do for _, t in ipairs(l.tags or {}) do tagSet[t] = true end end
  local cp = parseCode(deck.champion)
  local chosenKey = cp and canonKey(cp, false)
  local candidates, rest = {}, {}
  for _, ci in ipairs(main) do
    local p = parseCode(ci.code)
    local isChosen = chosenKey and p and canonKey(p, false) == chosenKey
    local matchesLegend = false
    if ci.supertype == "Champion" then
      for _, t in ipairs(ci.tags or {}) do if tagSet[t] then matchesLegend = true end end
    end
    if isChosen or matchesLegend then table.insert(candidates, ci) else table.insert(rest, ci) end
  end
  main = rest
  -- the deck code's chosen champion goes first (into the slot)
  table.sort(candidates, function(x, y)
    local px, py = parseCode(x.code), parseCode(y.code)
    local cx = chosenKey and px and canonKey(px, false) == chosenKey
    local cy = chosenKey and py and canonKey(py, false) == chosenKey
    if cx ~= cy then return cx end
    return false
  end)

  shuffleList(main)
  shuffleList(runes)

  local function tagged(ci, extra)
    local c = {}
    for k, v in pairs(ci) do c[k] = v end
    c.extraTag = extra
    return c
  end

  for i, ci in ipairs(legends) do
    local z = ZONES.legend
    spawnPile(color, { ci }, toWorld(color, z[1], z[2] + (i - 1) * 1.0, 0.6 + i * 0.1), true, nil)
  end
  -- Champion copies go to the hand (hidden from opponents); the player puts
  -- one into the Champion slot, the rest go back into the deck.
  local f = seatFrame(color)
  for i, ci in ipairs(candidates) do
    local hx, hz = localToWorld(f, -5.5 + (i - 1) * 1.5, f.handZ)
    spawnPile(color, { tagged(ci, "RB_ChampChoice") }, { hx, 3.6, hz }, true, nil)
  end
  spawnPile(color, main, zonePos(color, "mainDeck"), false, "Main Deck", function(o) o.shuffle() end)
  spawnPile(color, runes, zonePos(color, "runeDeck"), false, "Rune Deck", function(o) o.shuffle() end)
  spawnPile(color, battlefields, zonePos(color, "bfPick"), false, "Battlefields")
  spawnPile(color, side, zonePos(color, "sideboard"), false, "Sideboard")
  if #tokens > 0 then
    spawnPile(color, tokens, toWorld(color, BASE_AREA.x1 + 1.6, (BASE_AREA.z1 + BASE_AREA.z2) / 2), true, "Tokens")
  end

  -- Deck legality hints (main deck counts the one champion that stays out)
  local notes = {}
  local mainCount = #main + #candidates
  if mainCount < 40 then notes[#notes + 1] = "main deck has " .. mainCount .. " cards (40 expected)" end
  if #runes ~= 12 then notes[#notes + 1] = #runes .. " runes (12 expected)" end
  if #battlefields ~= 3 then notes[#notes + 1] = #battlefields .. " battlefields (3 expected)" end
  if #legends == 0 then notes[#notes + 1] = "no Legend found" end
  if #candidates == 0 then notes[#notes + 1] = "no champion matching the Legend found - put one in the Champion slot by hand" end
  if unknownTypes > 0 then
    notes[#notes + 1] = unknownTypes .. " card types unknown (lookup failed) - they went into the main deck"
  end
  for _, n in ipairs(notes) do warnings[#warnings + 1] = n end

  local msg = string.format("%s imported (%s): %s%s",
    color, sourceLabel,
    #legends > 0 and legends[1].name or "no Legend",
    #candidates > 0 and (" + " .. candidates[1].name) or "")
  broadcastToAll(msg, COLOR_RGB[color])
  if #candidates > 0 then
    broadcastToColor("Your champion copies are in your hand. Drag one onto the Champion slot (or right-click > " ..
      "Keep as champion); the others go back into your deck when the game starts.", color, { 0.9, 0.85, 0.6 })
  end
  if #warnings > 0 then
    printToColor("Import notes:\n- " .. table.concat(warnings, "\n- "), color, { 1, 0.75, 0.3 })
  end
  Wait.time(refreshControls, 1.0)
end

function importDeck(color, text)
  if not isSeat(color) then
    broadcastToColor("Take one of the seats for " .. mode().label .. " (" ..
      table.concat(mode().seats, ", ") .. ") to import a deck.", color, { 1, 0.4, 0.4 })
    return
  end
  if importing[color] then
    broadcastToColor("Already importing, hang on...", color, { 1, 0.8, 0.3 })
    return
  end
  if backURL() == "" then
    broadcastToColor("The host needs to paste the card back link on the table console first.", color, { 1, 0.4, 0.4 })
    return
  end

  local ok, deck, label = pcall(parseInput, text)
  if not ok then
    local msg = tostring(deck):gsub("^.-:%d+: ", "")
    broadcastToColor(msg, color, { 1, 0.4, 0.4 })
    return
  end

  -- Show exactly what was read, so a bad paste is obvious
  local total = 0
  for _, e in ipairs(deck.main) do total = total + e.count end
  local raw = trim(text):gsub("%s+", " ")
  printToColor("Read as " .. label .. " (" .. #raw .. " characters, starts '" .. raw:sub(1, 12) .. "...'): " ..
    #deck.main .. " different cards, " .. total .. " in total.", color, { 0.75, 0.8, 0.9 })
  if total < 10 then
    broadcastToColor("Only " .. total .. " card(s) found in what you pasted. Copy the deck code again on Piltover Archive " ..
      "(Export > deck code), press X, paste, then Import.", color, { 1, 0.6, 0.35 })
  end

  local codes, seen = {}, {}
  local function want(c) if c and not seen[c] then seen[c] = true; codes[#codes + 1] = c end end
  for _, e in ipairs(deck.main) do want(e.code) end
  for _, e in ipairs(deck.side) do want(e.code) end
  want(deck.champion)
  for _, c in ipairs(deck.legends) do want(c) end

  importing[color] = true
  local token = {}
  importing[color] = token
  Wait.time(function()
    if importing[color] == token then
      importing[color] = false
      broadcastToColor("Import timed out. Press Import again.", color, { 1, 0.5, 0.4 })
    end
  end, 60)
  broadcastToColor("Looking up " .. #codes .. " cards (the first import of a session takes a few seconds)...", color, { 0.8, 0.8, 0.8 })

  fetchCards(codes, function(info, warnings)
    importing[color] = false
    local found = 0
    for _, c in ipairs(codes) do if info[c] and info[c].image then found = found + 1 end end
    if found == 0 then
      broadcastToColor("Card database unreachable - no card images found. Details in chat. Try again, or type !rb test OGN-007.",
        color, { 1, 0.35, 0.3 })
    elseif found < #codes then
      broadcastToColor("Found " .. found .. " of " .. #codes .. " cards; the rest show as placeholders (see chat).", color, { 1, 0.75, 0.3 })
    end
    local ok2, err = pcall(buildDeck, color, deck, info, warnings, label)
    if not ok2 then broadcastToColor("Import failed: " .. tostring(err), color, { 1, 0.4, 0.4 }) end
  end)
end

-- Token cards by name ("Recruit", "Sprite", "Gold" ...)
function spawnTokenCard(color, name)
  name = trim(name)
  if name == "" then return end
  local function place(info)
    local pos = toWorld(color, (BASE_AREA.x1 + BASE_AREA.x2) / 2, (BASE_AREA.z1 + BASE_AREA.z2) / 2, 1.2)
    info.type = "Token"
    spawnPile(color, { info }, pos, true, nil)
  end
  httpJSON(API_BASE .. "/cards/name?fuzzy=" .. name:gsub("[^%w]", "+") .. "&size=20", function(data)
    local items = data and (data.items or data) or {}
    local pick
    for _, it in ipairs(items) do
      local cls = it.classification or {}
      local isToken = tostring(cls.supertype or ""):lower():find("token") or tostring(cls.type or ""):lower():find("token")
      if isToken and tostring(it.name or ""):lower():find(name:lower(), 1, true) then pick = it; break end
    end
    if pick then
      place(cardInfoFromItem(pick, tostring(pick.riftbound_id)))
    else
      place(placeholderInfo("TOKEN", name .. " (token)"))
      broadcastToColor("No token card art found for '" .. name .. "'; spawned a named placeholder.", color, { 1, 0.8, 0.4 })
    end
  end)
end

------------------------------------------------------------------------
-- TABLE QUERIES
------------------------------------------------------------------------

function castBox(cx, cz, sx, sz)
  return Physics.cast({
    origin = { cx, surfaceY + 5, cz }, direction = { 0, -1, 0 }, type = 3,
    size = { sx, 1, sz }, max_distance = 8,
  })
end

function findPileAt(pos)
  local best
  for _, h in ipairs(castBox(pos[1], pos[3], 3.0, 3.0)) do
    local o = h.hit_object
    if o and o.type == "Deck" then return o end
    if o and o.type == "Card" and not best then best = o end
  end
  return best
end

function pileCount(p)
  if not p then return 0 end
  if p.type == "Deck" then return p.getQuantity() end
  return 1
end

function cardsInArea(color, area)
  local a = toWorld(color, area.x1, area.z1)
  local b = toWorld(color, area.x2, area.z2)
  local x1, x2 = math.min(a[1], b[1]), math.max(a[1], b[1])
  local z1, z2 = math.min(a[3], b[3]), math.max(a[3], b[3])
  local out = {}
  for _, h in ipairs(castBox((x1 + x2) / 2, (z1 + z2) / 2, x2 - x1, z2 - z1)) do
    local o = h.hit_object
    if o and o.type == "Card" then out[#out + 1] = o end
  end
  return out
end

function ownerOf(obj)
  for c, _ in pairs(COLOR_RGB) do
    if obj.hasTag("RB_" .. c) then return c end
  end
  return nil
end

function seatedName(color)
  local p = Player[color]
  if p and p.seated and p.steam_name then return p.steam_name end
  return color
end

------------------------------------------------------------------------
-- CARD ACTIONS
------------------------------------------------------------------------

-- Moves the trash into the main deck, shuffles, an opponent gains 1 point.
function burnOut(color, after)
  local trash = findPileAt(zonePos(color, "trash"))
  local mainPos = zonePos(color, "mainDeck", 1.5)
  if trash then
    trash.setRotation({ 0, seatFrame(color).cardRotY, 180 })
    trash.setPosition(mainPos)
  end
  broadcastToAll(color .. " BURNED OUT: trash shuffled into the deck, an opponent gains 1 point.", { 1, 0.55, 0.3 })
  local opps = opponentsOf(color)
  if #opps == 1 or (mode().teams and true) then
    addPoints(scoreKey(opps[1]), 1)
  else
    broadcastToColor("Choose which opponent gains the point and press their + on the scoreboard.", color, { 1, 0.8, 0.4 })
  end
  Wait.time(function()
    local p = findPileAt(zonePos(color, "mainDeck"))
    if p and p.type == "Deck" then p.shuffle() end
    if after then after() end
  end, 1.0)
end

-- Deals n cards from a pile (deck or single card) into a player's hand.
function dealTo(pile, n, color)
  if not pile or n <= 0 then return end
  if pile.type == "Deck" then
    pile.deal(n, color)
  else
    local t = Player[color].getHandTransform()
    if t then
      pile.setRotation({ 0, seatFrame(color).cardRotY, 0 })
      pile.setPosition(t.position)
    end
  end
end

function drawCards(color, n, done)
  local pile = findPileAt(zonePos(color, "mainDeck"))
  local have = pileCount(pile)
  if have >= n then
    dealTo(pile, n, color)
    if done then done() end
    return
  end
  if have > 0 then dealTo(pile, have, color) end
  local remaining = n - have
  Wait.time(function()
    burnOut(color, function()
      local p2 = findPileAt(zonePos(color, "mainDeck"))
      if p2 then dealTo(p2, math.min(remaining, pileCount(p2)), color) end
      if done then done() end
    end)
  end, 0.3)
end

function channelRunes(color, n, done)
  local start = #cardsInArea(color, POOL_AREA)
  local function step(i)
    if i > n then if done then done() end return end
    local pile = findPileAt(zonePos(color, "runeDeck"))
    if not pile then
      broadcastToColor("Rune deck is empty.", color, { 1, 0.6, 0.3 })
      if done then done() end
      return
    end
    local slot = start + i - 1
    local row = math.floor(slot / POOL_SLOTS.count)
    local col = slot % POOL_SLOTS.count
    local pos = toWorld(color, POOL_SLOTS.x0 + col * POOL_SLOTS.dx + row * 0.5, POOL_SLOTS.z + row * 0.6, 0.6 + row * 0.2)
    local rot = { 0, seatFrame(color).cardRotY, 0 }
    if pile.type == "Deck" then
      pile.takeObject({ position = pos, rotation = rot, smooth = true })
    else
      pile.setPositionSmooth(pos, false, true)
      pile.setRotationSmooth(rot, false, true)
    end
    Wait.time(function() step(i + 1) end, 0.25)
  end
  step(1)
end

function readyAll(color, quiet)
  local inHand = {}
  for _, o in ipairs(Player[color].getHandObjects()) do inHand[o.getGUID()] = true end
  local rotY = seatFrame(color).cardRotY
  local n = 0
  for _, o in ipairs(getObjects()) do
    if (o.type == "Card" or o.type == "Deck") and o.hasTag("RB_" .. color)
        and not inHand[o.getGUID()] and not o.isSmoothMoving() and not o.hasTag("RB_Battlefield") then
      local r = o.getRotation()
      local diff = math.abs(((r.y - rotY) + 540) % 360 - 180)
      if diff > 20 then
        o.setRotationSmooth({ r.x, rotY, r.z }, false, true)
        n = n + 1
      end
    end
  end
  if not quiet then broadcastToColor("Readied " .. n .. " cards.", color, { 0.7, 0.9, 0.7 }) end
end

function shuffleMain(color)
  local pile = findPileAt(zonePos(color, "mainDeck"))
  if pile and pile.type == "Deck" then
    pile.shuffle()
    broadcastToAll(color .. " shuffled their deck.", COLOR_RGB[color])
  end
end

-- Peek: TTS's own deck viewer, visible only to this player
-- Where a card must go to land in the player's hand
function handPos(color)
  local p = Player[color]
  if p and p.seated then
    local t = p.getHandTransform()
    if t then return { t.position.x, t.position.y, t.position.z } end
  end
  local h = getObjectFromGUID(state.hands[color] or "")
  if h then local q = h.getPosition(); return { q.x, q.y, q.z } end
  return zonePos(color, "mainDeck", 2)
end

-- Peek: top cards go into your hand (only you see them), highlighted gold
function peekCards(color, n)
  local pile = findPileAt(zonePos(color, "mainDeck"))
  if not pile then
    broadcastToColor("Your main deck is empty.", color, { 1, 0.6, 0.3 })
    return
  end
  local total = math.min(n, pileCount(pile))
  local cards = {}
  local rot = { 0, seatFrame(color).cardRotY, 0 }
  local function step(i)
    local p = findPileAt(zonePos(color, "mainDeck"))
    if i > total or not p then
      Wait.time(function()
        addPending(color, cards, "peek")
        broadcastToAll(color .. " looks at the top " .. #cards .. " card" .. (#cards == 1 and "" or "s") .. " of their deck.", COLOR_RGB[color])
        broadcastToColor("Peeked cards are in your hand (gold outline). Drag one onto a button on your mat, " ..
          "or click a button to apply it to all of them.", color, { 0.9, 0.85, 0.6 })
      end, 0.5)
      return
    end
    if p.type == "Deck" then
      p.takeObject({ position = handPos(color), rotation = rot, smooth = false,
        callback_function = function(o) cards[#cards + 1] = o end })
    else
      p.setRotation(rot)
      p.setPosition(handPos(color))
      cards[#cards + 1] = p
    end
    Wait.time(function() step(i + 1) end, 0.25)
  end
  step(1)
end

------------------------------------------------------------------------
-- PENDING CARDS (after Peek / Reveal)
-- A button row appears on the mat. Click a button: it applies to every
-- pending card. Drag one card onto a button: it applies to that card only.
------------------------------------------------------------------------

pending = {}        -- color -> { cards = { obj, ... }, source = "peek"|"reveal" }
actionRects = {}    -- color -> { { act, x1, z1, x2, z2 }, ... }

ACTIONS = {
  { "top",    "Top of deck" },
  { "bottom", "Bottom of deck" },
  { "trash",  "Trash" },
  { "banish", "Banish" },
  { "hand",   "To hand" },
  { "done",   "Done" },
}

function alive(o)
  if o == nil then return false end
  local ok, g = pcall(function() return o.getGUID() end)
  return ok and g ~= nil
end

function addPending(color, cards, source)
  local cur = pending[color]
  if not cur or cur.source ~= source then
    if cur then for _, c in ipairs(cur.cards) do if alive(c) then pcall(function() c.highlightOff() end) end end end
    cur = { cards = {}, source = source }
    pending[color] = cur
  end
  for _, c in ipairs(cards) do
    if alive(c) then
      cur.cards[#cur.cards + 1] = c
      pcall(function() c.highlightOn({ 0.95, 0.78, 0.35 }) end)
    end
  end
  if #cur.cards > 0 then showActions(color) end
end

function clearPending(color)
  local cur = pending[color]
  if cur then
    for _, c in ipairs(cur.cards) do if alive(c) then pcall(function() c.highlightOff() end) end end
  end
  pending[color] = nil
  hideActions(color)
end

function removePending(color, obj)
  local cur = pending[color]
  if not cur then return end
  for i = #cur.cards, 1, -1 do
    if cur.cards[i] == obj or not alive(cur.cards[i]) then table.remove(cur.cards, i) end
  end
  pcall(function() obj.highlightOff() end)
  if #cur.cards == 0 then clearPending(color) end
end

function showActions(color)
  hideActions(color)
  local f = seatFrame(color)
  local u0, w = -11.4, 3.6
  actionRects[color] = {}
  for i, a in ipairs(ACTIONS) do
    local act = a[1]
    local name = "rba_" .. act .. "_" .. color
    _G[name] = function(obj, pc)
      if pc ~= color and not (Player[pc] and Player[pc].host) then return end
      runAction(color, act)
    end
    local u = u0 + (i - 1) * (w + 0.3)
    local p = toWorld(color, u, ACTION_ROW_V)
    -- drop target: the button plus some margin, in world coordinates
    local c1 = toWorld(color, u - w / 2 - 0.3, ACTION_ROW_V - 1.4)
    local c2 = toWorld(color, u + w / 2 + 0.3, ACTION_ROW_V + 1.4)
    table.insert(actionRects[color], { act,
      math.min(c1[1], c2[1]), math.min(c1[3], c2[3]), math.max(c1[1], c2[1]), math.max(c1[3], c2[3]) })
    spawnObject({
      type = "BlockSquare", position = { p[1], surfaceY - 0.55, p[3] },
      rotation = { 0, f.textRotY + BTN_ROT_OFFSET, 0 }, sound = false,
      callback_function = function(o)
        o.setLock(true)
        o.addTag("RB_Board")
        o.addTag("RB_Action_" .. color)
        local bp = btnParams(a[2], name, w, 1.1, (act == "done") and "normal" or "primary",
          (act == "done") and "Close this row (cards stay where they are)"
          or "Click: all highlighted cards. Or drag one card onto this button.")
        bp.position = { 0, 0.72, 0 }
        o.createButton(bp)
      end,
    })
  end
end

function hideActions(color)
  actionRects[color] = nil
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_Action_" .. color) then o.destruct() end
  end
end

function applyAction(color, act, cards)
  local list = {}
  for _, c in ipairs(cards) do
    if alive(c) then pcall(function() c.highlightOff() end); list[#list + 1] = c end
  end
  if #list == 0 then return end
  if act == "top" then putOnTop(color, list, "mainDeck")
  elseif act == "bottom" then recycleCards(color, list, "mainDeck", false)
  elseif act == "trash" then for _, c in ipairs(list) do moveToZone(c, color, "trash", true) end
  elseif act == "banish" then for _, c in ipairs(list) do moveToZone(c, color, "banish", true) end
  elseif act == "hand" then
    local hp = handPos(color)
    for _, c in ipairs(list) do
      c.setRotation({ 0, seatFrame(color).cardRotY, 0 })
      c.setPosition(hp)
    end
  end
end

function runAction(color, act)
  local cur = pending[color]
  if cur and act ~= "done" then applyAction(color, act, cur.cards) end
  clearPending(color)
end

-- Called on drop: was a pending card dropped onto one of the buttons?
function dropOnAction(obj)
  for color, cur in pairs(pending) do
    for _, c in ipairs(cur.cards) do
      if c == obj then
        local rects = actionRects[color]
        if not rects then return false end
        local p = obj.getPosition()
        for _, r in ipairs(rects) do
          if p.x >= r[2] and p.x <= r[4] and p.z >= r[3] and p.z <= r[5] then
            if r[1] ~= "done" then applyAction(color, r[1], { obj }) end
            removePending(color, obj)
            return true
          end
        end
        return false
      end
    end
  end
  return false
end

function putOnTop(color, cards, deckZone)
  for i, c in ipairs(cards) do
    Wait.time(function()
      local pile = findPileAt(zonePos(color, deckZone))
      c.setRotation({ 0, seatFrame(color).cardRotY, 180 })
      if pile and pile ~= c then
        pile.putObject(c)
      else
        c.setPosition(zonePos(color, deckZone, 0.8))
      end
    end, (i - 1) * 0.25)
  end
end


function revealSlot(color, i)
  local u = REVEAL_AREA.x1 + 1.45 + (i - 1) * 1.15
  if u > REVEAL_AREA.x2 - 1.45 then u = REVEAL_AREA.x2 - 1.45 end
  return toWorld(color, u, (REVEAL_AREA.z1 + REVEAL_AREA.z2) / 2, 0.6 + i * 0.05)
end

-- Reveal: top cards of the main deck go face up into the REVEAL spot
function revealCards(color, n)
  local start = #cardsInArea(color, REVEAL_AREA)
  local names, cards = {}, {}
  local function step(i)
    local pile = findPileAt(zonePos(color, "mainDeck"))
    if i > n or not pile then
      if #names > 0 then
        broadcastToAll(color .. " reveals: " .. table.concat(names, ", "), COLOR_RGB[color])
        Wait.time(function() addPending(color, cards, "reveal") end, 0.6)
      end
      if not pile and i <= n then broadcastToColor("No more cards in your main deck.", color, { 1, 0.6, 0.3 }) end
      return
    end
    local pos = revealSlot(color, start + i)
    local rot = { 0, seatFrame(color).cardRotY, 0 }
    if pile.type == "Deck" then
      local top = pile.getObjects()[1]
      names[#names + 1] = top and top.name or "?"
      pile.takeObject({ position = pos, rotation = rot, smooth = true,
        callback_function = function(o) cards[#cards + 1] = o end })
    else
      names[#names + 1] = pile.getName()
      pile.setPositionSmooth(pos, false, true)
      pile.setRotationSmooth(rot, false, true)
      cards[#cards + 1] = pile
    end
    Wait.time(function() step(i + 1) end, 0.25)
  end
  step(1)
end

-- Reveal a specific card (e.g. from your hand)
function revealCard(obj)
  local c = ownerOf(obj)
  if not c or not seatFrame(c) then return end
  local pos = revealSlot(c, #cardsInArea(c, REVEAL_AREA) + 1)
  obj.setPositionSmooth(pos, false, true)
  obj.setRotationSmooth({ 0, seatFrame(c).cardRotY, 0 }, false, true)
  broadcastToAll(c .. " reveals " .. obj.getName() .. ".", COLOR_RGB[c])
  Wait.time(function() addPending(c, { obj }, "reveal") end, 0.6)
end

-- Champion choice: keep one card, shuffle the other candidates into the deck
function keepChampion(color, keep)
  local others = {}
  for _, o in ipairs(getObjects()) do
    if o ~= keep and o.type == "Card" and o.hasTag("RB_ChampChoice") and o.hasTag("RB_" .. color) then
      others[#others + 1] = o
    end
  end
  if not keep and #others > 0 then keep = table.remove(others, 1) end
  for _, o in ipairs(others) do o.removeTag("RB_ChampChoice") end
  if keep then
    keep.removeTag("RB_ChampChoice")
    keep.setRotation({ 0, seatFrame(color).cardRotY, 0 })
    keep.setPosition(zonePos(color, "champion", 1.0))
  end
  if #others > 0 then recycleCards(color, others, "mainDeck", true) end
  -- shuffle in any case: copies may also have been put on the deck by hand
  Wait.time(function()
    local p = findPileAt(zonePos(color, "mainDeck"))
    if p and p.type == "Deck" then p.shuffle() end
  end, 1.0)
  if keep then
    broadcastToAll(color .. " sets " .. keep.getName() .. " as champion" ..
      (#others > 0 and ("; " .. #others .. " other cop" .. (#others == 1 and "y" or "ies") .. " shuffled into the deck.") or "."),
      COLOR_RGB[color])
  end
end

-- At game start: keep whatever sits in the Champion slot
function finalizeChampion(color)
  local open = false
  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and o.hasTag("RB_ChampChoice") and o.hasTag("RB_" .. color) then open = true end
  end
  if open then
    local inSlot = findPileAt(zonePos(color, "champion"))
    if inSlot and (inSlot.type ~= "Card" or not inSlot.hasTag("RB_ChampChoice")) then inSlot = nil end
    keepChampion(color, inSlot)
    return
  end
  -- Champion slot empty (e.g. all copies were put back into the deck):
  -- pull one copy out of the main deck into the slot.
  if findPileAt(zonePos(color, "champion")) then return end
  local deck = findPileAt(zonePos(color, "mainDeck"))
  if not deck or deck.type ~= "Deck" then return end
  for _, c in ipairs(deck.getData().ContainedObjects or {}) do
    for _, t in ipairs(c.Tags or {}) do
      if t == "RB_ChampChoice" and c.GUID then
        deck.takeObject({
          guid = c.GUID, position = zonePos(color, "champion", 1.0),
          rotation = { 0, seatFrame(color).cardRotY, 0 }, smooth = false,
          callback_function = function(o) o.removeTag("RB_ChampChoice") end,
        })
        broadcastToAll(color .. " champion: " .. tostring(c.Nickname or "champion") .. " (taken from the deck).", COLOR_RGB[color])
        return
      end
    end
  end
  broadcastToColor("No champion in your Champion slot - put one there before playing.", color, { 1, 0.6, 0.4 })
end

function moveToZone(obj, color, zone, faceUp)
  local p = zonePos(color, zone, 1.2)
  obj.setPositionSmooth(p, false, true)
  obj.setRotationSmooth({ 0, seatFrame(color).cardRotY, faceUp and 0 or 180 }, false, true)
end

-- Puts cards on the BOTTOM of their owner's main (or rune) deck.
function recycleCards(color, cards, deckZone, randomize)
  if #cards == 0 then return end
  if randomize then shuffleList(cards) end
  local pile = findPileAt(zonePos(color, deckZone))
  local datas = {}
  if pile then
    local pd = pile.getData()
    if pd.Name == "Deck" then
      for _, c in ipairs(pd.ContainedObjects or {}) do datas[#datas + 1] = c end
    else
      datas[#datas + 1] = pd
    end
  end
  for _, c in ipairs(cards) do datas[#datas + 1] = c.getData() end

  local pos = zonePos(color, deckZone)
  local rot = { 0, seatFrame(color).cardRotY, 180 }
  local name = (deckZone == "runeDeck") and "Rune Deck" or "Main Deck"
  if pile then pile.destruct() end
  for _, c in ipairs(cards) do c.destruct() end

  local data = (#datas == 1) and datas[1] or deckDataFromCards(datas, color, name, false)
  Wait.frames(function()
    spawnObjectData({ data = data, position = pos, rotation = rot })
  end, 2)
end

-- Markers: sturdy discs with their value printed on top. Discs (unlike cards)
-- never merge into a deck when dropped onto a unit.
MARKERS = {
  Buff    = { label = "+1",   name = "Buff (+1 Might, max 1 per unit)", tag = "RB_Buff",   tint = { 0.86, 0.69, 0.32 }, ink = { 0.10, 0.08, 0.03 } },
  Might2  = { label = "+2",   name = "Might +2",        tag = "RB_Might",  tint = { 0.93, 0.80, 0.42 }, ink = { 0.10, 0.08, 0.03 } },
  Might3  = { label = "+3",   name = "Might +3",        tag = "RB_Might",  tint = { 0.97, 0.86, 0.52 }, ink = { 0.10, 0.08, 0.03 } },
  Might5  = { label = "+5",   name = "Might +5",        tag = "RB_Might",  tint = { 1.00, 0.92, 0.65 }, ink = { 0.10, 0.08, 0.03 } },
  Damage1 = { label = "1",    name = "1 Damage",        tag = "RB_Damage", tint = { 0.80, 0.20, 0.16 }, ink = { 1, 0.95, 0.9 } },
  Damage3 = { label = "3",    name = "3 Damage",        tag = "RB_Damage", tint = { 0.66, 0.13, 0.10 }, ink = { 1, 0.95, 0.9 } },
  Damage5 = { label = "5",    name = "5 Damage",        tag = "RB_Damage", tint = { 0.50, 0.08, 0.06 }, ink = { 1, 0.95, 0.9 } },
  Stunned = { label = "STUN", name = "Stunned",         tag = "RB_Stun",   tint = { 0.55, 0.38, 0.85 }, ink = { 1, 1, 1 } },
  Tag     = { label = "TAG",  name = "Tag",             tag = "RB_Tag",    tint = { 0.92, 0.89, 0.82 }, ink = { 0.25, 0.22, 0.18 } },
}
MARKER_ORDER = { "Buff", "Might2", "Might3", "Might5", "Damage1", "Damage3", "Damage5", "Stunned", "Tag" }

-- Prints the value on top of a marker (buttons are not saved, so this runs
-- again on load and whenever a marker is spawned or dropped)
function labelMarker(o)
  if o == nil then return end
  local kind = o.memo
  local m = MARKERS[kind or ""]
  if not m then return end
  local text = m.label
  if kind == "Tag" then
    local n = o.getName()
    if n ~= "" and n ~= "Tag" then text = n:sub(1, 8) end
  end
  pcall(function()
    o.clearButtons()
    o.createButton({
      click_function = "rb_noop", function_owner = Global, label = text,
      position = { 0, 0.25, 0 }, rotation = { 0, 180, 0 }, width = 0, height = 0,
      font_size = (#text > 2) and 160 or 300, font_color = m.ink,
    })
  end)
end

function spawnMarkerObj(kind, pos, cb, rotY)
  local m = MARKERS[kind]
  spawnObject({
    type = "Checker_white", position = pos, rotation = { 0, rotY or 0, 0 }, scale = { 0.85, 0.85, 0.85 }, sound = false,
    callback_function = function(o)
      o.setColorTint(m.tint)
      o.setName(m.name)
      o.memo = kind
      o.addTag(m.tag)
      o.addTag("RB_Marker")
      labelMarker(o)
      if cb then cb(o) end
    end,
  })
end

-- From a card's right-click menu: put a marker on that card
function spawnMarker(kind, card)
  local p = card.getPosition()
  if kind == "Buff" then
    for _, h in ipairs(castBox(p.x, p.z, 2.6, 3.8)) do
      if h.hit_object and h.hit_object.hasTag("RB_Buff") then
        broadcastToAll("That unit already has a buff (max 1).", { 1, 0.8, 0.4 })
        return
      end
    end
  end
  local off = { Buff = { -0.7, 0.9 }, Might2 = { -0.7, 0.9 }, Damage1 = { 0.7, 0.9 }, Damage3 = { 0.7, 0.9 }, Stunned = { 0, -0.9 } }
  local o = off[kind] or { 0, 0 }
  spawnMarkerObj(kind, { p.x + o[1], p.y + 1.2, p.z + o[2] })
end

function addCardMenu(obj)
  if not obj or obj.type ~= "Card" or not obj.hasTag("Riftbound") then return end
  if menuAdded[obj.getGUID()] == obj then return end
  menuAdded[obj.getGUID()] = obj
  obj.addContextMenuItem("Buff  (+1 Might)", function(_, _, o) spawnMarker("Buff", o) end)
  obj.addContextMenuItem("Might +2", function(_, _, o) spawnMarker("Might2", o) end, true)
  obj.addContextMenuItem("Damage +1", function(_, _, o) spawnMarker("Damage1", o) end, true)
  obj.addContextMenuItem("Damage +3", function(_, _, o) spawnMarker("Damage3", o) end, true)
  obj.addContextMenuItem("Stun", function(_, _, o) spawnMarker("Stunned", o) end)
  if obj.hasTag("RB_ChampChoice") then
    obj.addContextMenuItem("Keep as champion", function(_, _, o)
      local c = ownerOf(o)
      if c and seatFrame(c) then keepChampion(c, o) end
    end)
  end
  obj.addContextMenuItem("Reveal to everyone", function(_, _, o) revealCard(o) end)
  obj.addContextMenuItem("Put on top of deck", function(_, _, o)
    local c = ownerOf(o)
    if c and seatFrame(c) then putOnTop(c, { o }, o.hasTag("RB_Rune") and "runeDeck" or "mainDeck") end
  end)
  if obj.hasTag("RB_Battlefield") then
    obj.addContextMenuItem("Print text on table", function(_, _, o) imprintBattlefield(o) end)
  end
  obj.addContextMenuItem("To trash", function(_, _, o)
    local c = ownerOf(o); if c and seatFrame(c) then moveToZone(o, c, "trash", true) end
  end)
  obj.addContextMenuItem("Recycle (bottom of deck)", function(_, _, o)
    local c = ownerOf(o)
    if c and seatFrame(c) then
      recycleCards(c, { o }, o.hasTag("RB_Rune") and "runeDeck" or "mainDeck", false)
    end
  end)
  obj.addContextMenuItem("Banish", function(_, _, o)
    local c = ownerOf(o); if c and seatFrame(c) then moveToZone(o, c, "banish", true) end
  end)
  obj.addContextMenuItem("Return to hand", function(_, _, o)
    local c = ownerOf(o)
    if c and Player[c] then
      local t = Player[c].getHandTransform()
      if t then
        o.setRotation({ 0, seatFrame(c) and seatFrame(c).cardRotY or 0, 0 })
        o.setPosition(t.position)
      end
    end
  end)
end

function onObjectSpawn(obj)
  Wait.frames(function()
    if obj ~= nil then
      addCardMenu(obj)
      if obj.hasTag("RB_Marker") then labelMarker(obj) end
    end
  end, 1)
end

dragging = {}       -- picker color -> { obj, owner, deckZone }
baseLines = {}

function dropRect(color, deckZone, which)
  local u, v
  if which == "top" then
    u, v = ZONES[deckZone][1], ZONES[deckZone][2]
  else
    u, v = DROP_BOTTOM[deckZone][1], DROP_BOTTOM[deckZone][2]
  end
  local h = (which == "top") and (CARD_H + 0.3) or DROP_H
  local w = (which == "top") and (CARD_W + 0.3) or DROP_W
  local a = toWorld(color, u - w / 2, v - h / 2)
  local b = toWorld(color, u + w / 2, v + h / 2)
  return math.min(a[1], b[1]), math.min(a[3], b[3]), math.max(a[1], b[1]), math.max(a[3], b[3])
end

function showDropZones(color, deckZone)
  local lines = {}
  for _, l in ipairs(baseLines) do lines[#lines + 1] = l end
  local glow = { 0.98, 0.84, 0.45 }
  matRect(lines, color, ZONES[deckZone][1], ZONES[deckZone][2], CARD_W + 0.5, CARD_H + 0.5, glow, 0.2, 0.3)
  matRect(lines, color, DROP_BOTTOM[deckZone][1], DROP_BOTTOM[deckZone][2], DROP_W, DROP_H, glow, 0.2, 0.3)
  Global.setVectorLines(lines)
  local f = seatFrame(color)
  local bp = toWorld(color, DROP_BOTTOM[deckZone][1], DROP_BOTTOM[deckZone][2]); bp[2] = surfaceY + 0.3
  spawnLabel("BOTTOM", bp, f.textRotY, 26, glow)
  local tp = toWorld(color, ZONES[deckZone][1], ZONES[deckZone][2] + CARD_H / 2 + 0.55); tp[2] = surfaceY + 0.3
  spawnLabel("TOP", tp, f.textRotY, 26, glow)
end

function hideDropZones()
  Global.setVectorLines(baseLines)
  for _, o in ipairs(getObjects()) do
    if o.type == "3DText" and (o.TextTool.getValue() == "BOTTOM" or o.TextTool.getValue() == "TOP") then o.destruct() end
  end
end

function onObjectPickUp(color, obj)
  safeCall("onObjectPickUp", function()
    if obj.hasTag("RB_Dispenser") then refillDispenser(obj, color); return end
    if obj.type == "Card" and obj.hasTag("RB_Battlefield") then
      local slot, d = nearestSlot(obj.getPosition())
      if slot and d <= 4 then clearBattlefieldText(slot) end
    end
    if obj.type ~= "Card" then return end
    local owner = ownerOf(obj)
    if not owner or not seatFrame(owner) or obj.hasTag("RB_Battlefield") or obj.hasTag("RB_Legend") then return end
    local isRune = obj.hasTag("RB_Rune") or (obj.getName():find("Rune$") ~= nil)
    local deckZone = isRune and "runeDeck" or "mainDeck"
    dragging[color] = { obj = obj, owner = owner, deckZone = deckZone }
    showDropZones(owner, deckZone)
  end)
end

function onObjectDrop(color, obj)
  safeCall("onObjectDrop", function()
    if obj.hasTag("RB_Marker") then labelMarker(obj) end
    if obj.type == "Card" and obj.hasTag("RB_Battlefield") then
      Wait.time(function()
        if not alive(obj) then return end
        local slot, d = nearestSlot(obj.getPosition())
        if slot and d <= 4 then imprintBattlefield(obj) end
      end, 0.8)
    end
    -- a champion copy dropped onto the Champion slot confirms the choice
    if obj.type == "Card" and obj.hasTag("RB_ChampChoice") then
      Wait.time(function()
        if not alive(obj) or not obj.hasTag("RB_ChampChoice") then return end
        local c = ownerOf(obj)
        if not c or not seatFrame(c) then return end
        local slot, p = zonePos(c, "champion"), obj.getPosition()
        if math.abs(p.x - slot[1]) < 2.2 and math.abs(p.z - slot[3]) < 2.2 then keepChampion(c, obj) end
      end, 0.6)
    end
    local d = dragging[color]
    if d and d.obj == obj then
      dragging[color] = nil
      hideDropZones()
    else
      d = nil
    end
    if obj.type == "Card" and dropOnAction(obj) then return end
    if not d then return end
    local p = obj.getPosition()
    local function inside(which)
      local x1, z1, x2, z2 = dropRect(d.owner, d.deckZone, which)
      return p.x >= x1 - 0.4 and p.x <= x2 + 0.4 and p.z >= z1 - 0.4 and p.z <= z2 + 0.4
    end
    local deckName = (d.deckZone == "runeDeck") and "rune deck" or "deck"
    if inside("bottom") then
      recycleCards(d.owner, { obj }, d.deckZone, false)
      broadcastToColor("Put on the bottom of your " .. deckName .. ".", color, { 0.8, 0.8, 0.8 })
    elseif inside("top") then
      Wait.frames(function()
        if alive(obj) then putOnTop(d.owner, { obj }, d.deckZone) end
      end, 10)
      broadcastToColor("Put on top of your " .. deckName .. ".", color, { 0.8, 0.8, 0.8 })
    end
  end)
end

-- A card dropped onto a token pile merges with it: treat that as "put it
-- back". The stack is removed and the pile card is restored on its spot.
mergeHandled = {}
function onObjectEnterContainer(container, obj)
  safeCall("onObjectEnterContainer", function()
    if container == nil or container.type ~= "Deck" then return end
    local cg = container.getGUID()
    if mergeHandled[cg] then return end
    Wait.frames(function()
      if mergeHandled[cg] or not alive(container) then return end
      local data = container.getData()
      local pileCard, home
      for _, c in ipairs(data.ContainedObjects or {}) do
        for _, t in ipairs(c.Tags or {}) do
          if t == "RB_Dispenser" then
            local ok, h = pcall(JSON.decode, c.GMNotes or "")
            if ok and type(h) == "table" and h.p then pileCard, home = c, h end
          end
        end
      end
      if not pileCard then return end
      mergeHandled[cg] = true
      container.destruct()
      pileCard.Transform.posX, pileCard.Transform.posY, pileCard.Transform.posZ = home.p[1], home.p[2], home.p[3]
      spawnObjectData({
        data = pileCard, position = home.p, rotation = home.r,
        callback_function = function(n)
          n.setPosition(home.p)
          n.setRotation(home.r)
          mergeHandled[cg] = nil
        end,
      })
    end, 3)
  end)
end

-- Runs an event handler; an error is reported with the handler's name
function safeCall(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    print("[Riftbound] " .. name .. ": " .. tostring(err))
  end
end
function onObjectLeaveContainer(_, obj)
  Wait.frames(function()
    if obj == nil or not alive(obj) then return end
    if state.game and obj.hasTag("RB_ChampChoice") then obj.removeTag("RB_ChampChoice") end
    addCardMenu(obj)
  end, 1)
end

function clearArea(color)
  for _, obj in ipairs(getObjects()) do
    if obj.hasTag("RB_" .. color) then obj.destruct() end
  end
end

------------------------------------------------------------------------
-- SCORE
------------------------------------------------------------------------

function scoreKey(color)
  local t = mode().teams
  if t then
    for name, members in pairs(t) do
      for _, c in ipairs(members) do if c == color then return "Team" .. name end end
    end
  end
  return color
end

function scoreKeys()
  local t = mode().teams
  if t then return { "TeamA", "TeamB" } end
  return mode().seats
end

function scoreLabel(key)
  local t = mode().teams
  if t and key == "TeamA" then return "Team " .. t.A[1] .. "/" .. t.A[2] end
  if t and key == "TeamB" then return "Team " .. t.B[1] .. "/" .. t.B[2] end
  return key
end

function opponentsOf(color)
  local out = {}
  local mine = scoreKey(color)
  for _, c in ipairs(mode().seats) do
    if scoreKey(c) ~= mine then out[#out + 1] = c end
  end
  return out
end

function addPoints(key, d)
  state.points[key] = math.max(0, (state.points[key] or 0) + d)
  refreshScore()
  local v = state.points[key]
  if d > 0 then
    broadcastToAll(scoreLabel(key) .. ": " .. v .. " / " .. mode().victory .. " points", { 0.9, 0.85, 0.6 })
  end
  if v >= mode().victory then
    local best = true
    for _, k in ipairs(scoreKeys()) do
      if k ~= key and (state.points[k] or 0) >= v then best = false end
    end
    if best then
      broadcastToAll(scoreLabel(key) .. " reached " .. mode().victory .. " points and WINS (checked at cleanup).", { 1, 0.85, 0.2 })
    end
  end
end

function addXP(color, d)
  state.xp[color] = math.max(0, (state.xp[color] or 0) + d)
  refreshScore()
end

------------------------------------------------------------------------
-- GAME FLOW
------------------------------------------------------------------------

function currentPlayer()
  local g = state.game
  if not g or not g.order then return nil end
  return g.order[g.turnIdx]
end

function announce(text, rgb) broadcastToAll(text, rgb or { 0.95, 0.85, 0.6 }) end

function startGame(host, firstChoice)
  local m = mode()
  for _, c in ipairs(m.seats) do
    if not findPileAt(zonePos(c, "mainDeck")) then
      broadcastToColor(c .. " has no deck in their Main Deck zone. Import all decks first.", host, { 1, 0.5, 0.4 })
      return
    end
  end

  -- First player: random unless the host picked one
  local first = firstChoice
  if not first or not isSeat(first) then first = m.seats[math.random(1, #m.seats)] end
  local cycle, order, startIdx = CYCLES[state.mode], {}, 1
  for i, c in ipairs(cycle) do if c == first then startIdx = i end end
  for i = 0, #cycle - 1 do order[#order + 1] = cycle[((startIdx - 1 + i) % #cycle) + 1] end

  state.game = {
    order = order, turnIdx = 1, turn = 0, phase = "Setup",
    mulligan = {}, firstTurnDone = {},
  }
  state.points, state.xp = {}, {}
  for _, k in ipairs(scoreKeys()) do state.points[k] = 0 end
  for _, c in ipairs(m.seats) do state.xp[c] = 0 end

  announce("New " .. m.label .. " game. Turn order: " .. table.concat(order, " > ") .. ". First player: " .. first .. ".")

  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_BFText") then o.destruct() end
  end
  for _, c in ipairs(order) do finalizeChampion(c) end
  placeBattlefields(order)

  -- Setup rule: shuffle the main decks, then draw the opening hands
  Wait.time(function()
    for _, c in ipairs(order) do
      local p = findPileAt(zonePos(c, "mainDeck"))
      if p and p.type == "Deck" then p.shuffle() end
    end
  end, 2.0)
  Wait.time(function()
    for _, c in ipairs(order) do drawCards(c, 4) end
  end, 2.8)
  Wait.time(function()
    state.game.phase = "Mulligan"
    refreshScore()
    announce("MULLIGAN: drag up to 2 cards onto your BASE, then press Mulligan done on your side of the table (empty Base = keep your hand).")
  end, 4.4)
  refreshScore()
end

-- Battlefield rules text printed around its slot, readable from every seat
function wrapText(t, width)
  local lines, line = {}, ""
  for word in tostring(t):gmatch("%S+") do
    if #line + #word + 1 > width and #line > 0 then
      lines[#lines + 1] = line
      line = word
    else
      line = (#line > 0) and (line .. " " .. word) or word
    end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return table.concat(lines, "\n")
end

function nearestSlot(pos)
  local best, bestD
  for _, x in ipairs(bfSlots()) do
    local d = math.abs(pos.x - x) + math.abs(pos.z)
    if not bestD or d < bestD then best, bestD = x, d end
  end
  return best, bestD
end

function clearBattlefieldText(slotX)
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_BFText") and o.memo == tostring(slotX) then o.destruct() end
  end
end

function imprintBattlefield(card)
  local p = card.getPosition()
  local best, bestD
  for _, x in ipairs(bfSlots()) do
    local d = math.abs(p.x - x) + math.abs(p.z)
    if not bestD or d < bestD then best, bestD = x, d end
  end
  if not best or bestD > 8 then
    broadcastToAll("Put the battlefield on a battlefield spot first.", { 1, 0.7, 0.4 })
    return
  end
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_BFText") and o.memo == tostring(best) then o.destruct() end
  end
  local rules = card.memo
  if not rules or rules == "" then
    -- older imports: the rules text sits between the stats and the [code] line
    local d = card.getDescription() or ""
    rules = d:gsub("%[[^%]]*%]%s*$", ""):match("\n\n(.*)$") or ""
    rules = rules:gsub("^%s+", ""):gsub("%s+$", "")
  end
  if rules == "" then
    local code = card.getGMNotes()
    local p = parseCode(code or "")
    if p and official then
      local ok, item = pcall(officialItem, canonKey(p, true))
      if not ok or not item then ok, item = pcall(officialItem, canonKey(p, false)) end
      if ok and item and item.text and item.text.plain then
        rules = item.text.plain
        card.memo = rules
      end
    end
  end
  if rules == "" then
    broadcastToAll(card.getName() .. " has no rules text to print.", { 0.9, 0.8, 0.6 })
    return
  end
  local text = card.getName() .. "\n" .. wrapText(rules, 34)
  local y = surfaceY + 0.3
  local spots = { { best, -3.3, 0 }, { best, 3.3, 180 } }
  if state.mode ~= "Duel" then
    spots[#spots + 1] = { best - 4.6, 0, 90 }
    spots[#spots + 1] = { best + 5.6, 0, 270 }
  end
  for _, sp in ipairs(spots) do
    spawnObject({
      type = "3DText", position = { sp[1], y, sp[2] }, rotation = { 90, sp[3], 0 }, sound = false,
      callback_function = function(o)
        o.TextTool.setValue(text)
        o.TextTool.setFontSize(13)
        o.TextTool.setFontColor({ 0.85, 0.78, 0.6 })
        o.setLock(true)
        o.interactable = false
        o.memo = tostring(best)
        o.addTag("RB_BFText")
        o.addTag("RB_Board")
      end,
    })
  end
end

function placeBattlefields(order)
  local m = mode()
  local contributors = {}
  for i, c in ipairs(order) do
    if m.firstGivesBF or i > 1 then contributors[#contributors + 1] = c end
  end
  local slots = bfSlots()
  for i, c in ipairs(contributors) do
    local slotX = slots[i]
    if slotX then
      local pile = findPileAt(zonePos(c, "bfPick"))
      if not pile then
        broadcastToAll(c .. " has no battlefields to contribute.", { 1, 0.6, 0.4 })
      else
        local dest = { slotX, surfaceY + 1.0, 0 }
        local rot = { 0, 180, 0 }
        if pile.type == "Deck" then
          local idx = math.random(0, pile.getQuantity() - 1)
          pile.takeObject({ index = idx, position = dest, rotation = rot, smooth = true,
            callback_function = function(o)
              o.addTag("RB_Battlefield")
              Wait.time(function() imprintBattlefield(o) end, 1.2)
            end })
        else
          pile.setPositionSmooth(dest, false, true)
          pile.setRotationSmooth(rot, false, true)
          pile.addTag("RB_Battlefield")
          Wait.time(function() imprintBattlefield(pile) end, 1.5)
        end
      end
    end
  end
  if not m.firstGivesBF then
    announce(order[1] .. " goes first, so their battlefields stay out of play.")
  end
end

function mulliganDone(color)
  local g = state.game
  if not g or g.phase ~= "Mulligan" then
    broadcastToColor("Mulligans only happen at the start of a game.", color, { 1, 0.7, 0.4 })
    return
  end
  if g.mulligan[color] then return end
  if g.phase ~= "Mulligan" then
    broadcastToColor("Wait until the opening hands are dealt.", color, { 1, 0.7, 0.4 })
    return
  end
  local set = {}
  for _, o in ipairs(cardsInArea(color, BASE_AREA)) do
    if o.hasTag("RB_" .. color) then set[#set + 1] = o end
  end
  if #set > 2 then
    broadcastToColor("You can set aside at most 2 cards (found " .. #set .. " in your Base).", color, { 1, 0.5, 0.4 })
    return
  end
  g.mulligan[color] = true
  if #set > 0 then
    -- Draw the same number, then recycle the set-aside cards to the bottom
    drawCards(color, #set, function()
      Wait.time(function() recycleCards(color, set, "mainDeck", true) end, 0.4)
    end)
    announce(color .. " mulliganed " .. #set .. " card" .. (#set == 1 and "" or "s") .. ".", COLOR_RGB[color])
  else
    announce(color .. " keeps their hand.", COLOR_RGB[color])
  end
  local all = true
  for _, c in ipairs(g.order) do if not g.mulligan[c] then all = false end end
  if all then Wait.time(beginFirstTurn, 2.0) end
  refreshScore()
end

function beginFirstTurn()
  local g = state.game
  if not g or g.phase == "Main" or (g.turn or 0) > 0 then return end
  g.turnIdx = 1
  g.turn = 1
  startTurn()
end

-- First-turn adjustments per mode
function firstTurnRunes(color)
  local g = state.game
  if g.firstTurnDone[color] then return 2 end
  if state.mode == "Duel" then
    return (g.order[2] == color) and 3 or 2
  end
  return (g.order[#g.order] == color) and 3 or 2
end

function firstTurnSkipsDraw(color)
  local g = state.game
  if g.firstTurnDone[color] or state.mode == "Duel" then return false end
  return g.order[1] == color
end

function setPhase(p)
  state.game.phase = p
  refreshScore()
end

function runPhase(p, nextStep)
  local g = state.game
  local c = currentPlayer()
  setPhase(p)
  if p == "Awaken" then
    readyAll(c, true)
    Wait.time(nextStep, 0.6)
  elseif p == "Beginning" then
    broadcastToAll(c .. " - Beginning: " .. PHASE_HINT.Beginning, COLOR_RGB[c])
    Wait.time(nextStep, 0.6)
  elseif p == "Channel" then
    local n = firstTurnRunes(c)
    if n > 2 then announce(c .. " channels an extra rune on their first turn.", COLOR_RGB[c]) end
    channelRunes(c, n, function() Wait.time(nextStep, 0.3) end)
  elseif p == "Draw" then
    if firstTurnSkipsDraw(c) then
      announce(c .. " goes first and skips their first draw.", COLOR_RGB[c])
      Wait.time(nextStep, 0.3)
    else
      drawCards(c, 1, function() Wait.time(nextStep, 0.3) end)
    end
  elseif p == "Main" then
    broadcastToAll(c .. " - Main phase. " .. PHASE_HINT.Main, COLOR_RGB[c])
    if nextStep then nextStep() end
  end
end

function startTurn()
  local g = state.game
  local c = currentPlayer()
  announce("TURN " .. g.turn .. " - " .. seatedName(c) .. " (" .. c .. ")", COLOR_RGB[c])
  syncTurns()
  if state.autoPhases then
    runPhase("Awaken", function()
      runPhase("Beginning", function()
        runPhase("Channel", function()
          runPhase("Draw", function() runPhase("Main") end)
        end)
      end)
    end)
  else
    setPhase("Awaken")
    broadcastToColor("Manual phases: press Next phase to run each step.", c, { 0.8, 0.8, 0.8 })
  end
end

function nextPhase(who)
  local g = state.game
  if not g or not g.order then return end
  if g.phase == "Mulligan" or g.phase == "Setup" then
    broadcastToColor("Finish mulligans first (or host: Skip mulligan).", who, { 1, 0.7, 0.4 })
    return
  end
  local idx = 1
  for i, p in ipairs(PHASES) do if p == g.phase then idx = i end end
  if g.phase == "Main" or g.phase == "End" then endTurn(who); return end
  -- Manual mode: run the current phase's action, then step forward
  runPhase(g.phase, function() setPhase(PHASES[idx + 1]) end)
end

function endTurn(who)
  local g = state.game
  if not g or not g.order or g.turn == 0 then return end
  local c = currentPlayer()
  g.firstTurnDone[c] = true
  setPhase("End")
  -- All units heal at end of turn
  local healed = 0
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_Damage") then o.destruct(); healed = healed + 1 end
  end
  broadcastToAll(c .. " ends their turn." .. (healed > 0 and " Units healed." or ""), COLOR_RGB[c])
  Wait.time(function()
    g.turnIdx = (g.turnIdx % #g.order) + 1
    g.turn = g.turn + 1
    startTurn()
  end, 0.8)
end

function canControlTurn(player)
  if player.host then return true end
  return player.color == currentPlayer()
end

function resetGame()
  state.game = nil
  state.points, state.xp = {}, {}
  Turns.enable = false
  refreshScore()
end

------------------------------------------------------------------------
-- BOARD BUILD
-- The built-in TTS table is disabled (Table_None). The mod builds its own
-- table top sized for the mode, so every seat fits inside the rails.
------------------------------------------------------------------------

function measureSurface()
  local hits = Physics.cast({ origin = { 0, 30, 3 }, direction = { 0, -1, 0 }, type = 1, max_distance = 60 })
  local top
  for _, h in ipairs(hits) do
    if h.hit_object and h.hit_object.hasTag("RB_Mat") then
      if not top or h.point.y > top then top = h.point.y end
    end
  end
  if top then surfaceY = top end
end

-- Rectangle in a seat's local frame (absolute local z, not mat coords)
function seatRect(lines, color, u1, z1, u2, z2, rgb, thick, dy)
  local f = seatFrame(color)
  local y = surfaceY + (dy or 0.03)
  local pts = {}
  for _, c in ipairs({ { u1, z1 }, { u2, z1 }, { u2, z2 }, { u1, z2 } }) do
    local x, z = localToWorld(f, c[1], c[2])
    pts[#pts + 1] = { x, y, z }
  end
  table.insert(lines, { points = pts, color = rgb, thickness = thick or 0.08, loop = true })
end

function matRect(lines, color, cu, cv, w, h, rgb, thick, dy)
  local mz = seatFrame(color).matZ
  seatRect(lines, color, cu - w / 2, mz + cv - h / 2, cu + w / 2, mz + cv + h / 2, rgb, thick, dy)
end

function worldRect(lines, cx, cz, w, h, rgb, thick)
  local y = surfaceY + 0.03
  table.insert(lines, {
    points = { { cx - w / 2, y, cz - h / 2 }, { cx + w / 2, y, cz - h / 2 }, { cx + w / 2, y, cz + h / 2 }, { cx - w / 2, y, cz + h / 2 } },
    color = rgb, thickness = thick or 0.08, loop = true,
  })
end

function zoneSize(key, z)
  if key == "dice" then return 2.8, 2.8 end
  local w, h = CARD_W + 0.3, CARD_H + 0.3
  if z[4] then w, h = 4.4, 3.1 end
  return w, h
end

function drawZones()
  local lines = {}
  local useMat, useBf = matURL() ~= "", bfURL() ~= ""
  for _, color in ipairs(mode().seats) do
    local c = COLOR_RGB[color]
    local dim = { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }
    if not useMat then
      for key, z in pairs(ZONES) do
        local w, h = zoneSize(key, z)
        matRect(lines, color, z[1], z[2], w, h, c)
      end
      for _, a in ipairs({ BASE_AREA, POOL_AREA, REVEAL_AREA }) do
        matRect(lines, color, (a.x1 + a.x2) / 2, (a.z1 + a.z2) / 2, a.x2 - a.x1, a.z2 - a.z1, c)
      end
    end
    matRect(lines, color, 0, 0, MAT_W + 0.4, MAT_D + 0.4, c, 0.12)
    local f = seatFrame(color)
    seatRect(lines, color, -23.2, f.consoleZ - 1.85, 23.2, f.consoleZ + 1.85, dim, 0.06)
  end
  if not useBf then
    for _, x in ipairs(bfSlots()) do
      worldRect(lines, x, 0, 12.5, 12.6, GOLD, 0.1)
      worldRect(lines, x, 0, CARD_H + 0.3, CARD_W + 0.3, GOLD)
      worldRect(lines, x + 4.2, 0, CARD_W * 0.8, CARD_H * 0.8, { 0.5, 0.42, 0.25 })
    end
  end
  baseLines = lines
  Global.setVectorLines(lines)
end

-- Snap points: every card place on every seat, rune pool slots, battlefields
function setSnaps()
  local snaps = {}
  local function add(p, rotY)
    snaps[#snaps + 1] = { position = { p[1], surfaceY + 0.05, p[3] }, rotation = { 0, rotY, 0 }, rotation_snap = true }
  end
  for _, color in ipairs(mode().seats) do
    local f = seatFrame(color)
    for key, z in pairs(ZONES) do
      if key ~= "dice" then add(toWorld(color, z[1], z[2]), f.cardRotY) end
    end
    for i = 0, POOL_SLOTS.count - 1 do
      add(toWorld(color, POOL_SLOTS.x0 + i * POOL_SLOTS.dx, POOL_SLOTS.z), f.cardRotY)
    end
    add(toWorld(color, (REVEAL_AREA.x1 + REVEAL_AREA.x2) / 2, (REVEAL_AREA.z1 + REVEAL_AREA.z2) / 2), f.cardRotY)
  end
  for _, x in ipairs(bfSlots()) do
    add({ x, 0, 0 }, 180)
    add({ x + 4.2, 0, 0 }, 180)
  end
  Global.setSnapPoints(snaps)
end

function spawnLabel(text, pos, rotY, size, rgb)
  spawnObject({
    type = "3DText", position = pos, rotation = { 90, rotY, 0 }, sound = false,
    callback_function = function(o)
      o.TextTool.setValue(text)
      o.TextTool.setFontSize(size or 40)
      o.TextTool.setFontColor(rgb or { 0.85, 0.8, 0.7 })
      o.setLock(true)
      o.interactable = false
      o.addTag("RB_Board")
    end,
  })
end

function spawnLabels()
  local y = surfaceY + 0.05
  local useMat, useBf = matURL() ~= "", bfURL() ~= ""
  if not useMat then
    for _, color in ipairs(mode().seats) do
      local f = seatFrame(color)
      local base = COLOR_RGB[color]
      local rgb = { base[1] * 0.6 + 0.35, base[2] * 0.6 + 0.35, base[3] * 0.6 + 0.35 }
      for key, z in pairs(ZONES) do
        local _, h = zoneSize(key, z)
        local p = toWorld(color, z[1], z[2] - h / 2 - 0.45); p[2] = y
        spawnLabel(z[3], p, f.textRotY, 22, rgb)
      end
      for _, a in ipairs({ BASE_AREA, POOL_AREA, REVEAL_AREA }) do
        local p = toWorld(color, (a.x1 + a.x2) / 2, a.z1 - 0.45); p[2] = y
        spawnLabel(a.label, p, f.textRotY, 26, rgb)
      end
    end
  end
  if not useBf then
    for _, x in ipairs(bfSlots()) do
      spawnLabel("BATTLEFIELD", { x, y + 0.25, 5.0 }, 180, 24, GOLD)
      spawnLabel("BATTLEFIELD", { x, y + 0.25, -5.0 }, 0, 24, GOLD)
      spawnLabel("HIDDEN", { x + 4.2, y, -2.0 }, 0, 14, { 0.6, 0.5, 0.3 })
    end
  end
end

function spawnBlock(pos, scale, tint, name, tags)
  spawnObject({
    type = "BlockSquare", position = pos, scale = scale, sound = false,
    callback_function = function(o)
      o.setColorTint(tint)
      o.setLock(true)
      o.interactable = false
      o.setName(name or "")
      for _, t in ipairs(tags) do o.addTag(t) end
    end,
  })
end

function spawnTable()
  local w, h = matSize()
  spawnBlock({ 0, 0.7, 0 }, { w, 1.2, h }, { 0.075, 0.09, 0.115 }, "Riftbound table", { "RB_Board", "RB_Mat" })
  local rail = { 0.20, 0.16, 0.11 }
  local ry, rs = 1.55, 0.9
  spawnBlock({ 0, ry,  h / 2 + 0.6 }, { w + 2.4, rs, 1.2 }, rail, "", { "RB_Board" })
  spawnBlock({ 0, ry, -h / 2 - 0.6 }, { w + 2.4, rs, 1.2 }, rail, "", { "RB_Board" })
  spawnBlock({  w / 2 + 0.6, ry, 0 }, { 1.2, rs, h }, rail, "", { "RB_Board" })
  spawnBlock({ -w / 2 - 0.6, ry, 0 }, { 1.2, rs, h }, rail, "", { "RB_Board" })
  spawnBlock({ 0, -1.5, 0 }, { w + 2.4, 3.2, h + 2.4 }, { 0.05, 0.05, 0.06 }, "", { "RB_Board" })
end

-- Spawns an image tile, scales it to exactly w x h world units (measured
-- unrotated), then turns it to rotY.
function spawnImageTile(url, pos, rotY, w, h)
  local o = spawnObject({ type = "Custom_Tile", position = pos, rotation = { 0, 0, 0 }, sound = false })
  o.setCustomObject({ image = url, type = 0, thickness = 0.1, stackable = false })
  local tile = o.reload()
  Wait.time(function()
    if tile == nil then return end
    tile.setRotation({ 0, 0, 0 })
    local b = tile.getBounds()
    local s = tile.getScale()
    if b.size.x > 0 and b.size.z > 0 then
      tile.setScale({ s.x * w / b.size.x, s.y, s.z * h / b.size.z })
    end
    tile.setPosition(pos)
    tile.setRotation({ 0, rotY, 0 })
    tile.setLock(true)
    tile.interactable = false
    tile.addTag("RB_Board")
  end, 2.5)
end

function spawnSeatMats()
  local url = matURL()
  if url == "" then return end
  for _, color in ipairs(mode().seats) do
    local f = seatFrame(color)
    local p = toWorld(color, 0, 0); p[2] = surfaceY + 0.02
    -- image top points toward the table centre for the seat owner
    spawnImageTile(url, p, f.cardRotY + (state.matFlip and 180 or 0), MAT_W, MAT_D)
  end
end

function spawnBfMats()
  local url = bfURL()
  if url == "" then return end
  for _, x in ipairs(bfSlots()) do
    spawnImageTile(url, { x, surfaceY + 0.02, 0 }, 180 + (state.matFlip and 180 or 0), 12.5, 12.6)
  end
end

-- Dispensers: a token lies on its home spot; picking it up leaves a fresh
-- one behind. Used for markers, dice and the game's token cards.
function makeDispenser(o, pos, rot)
  o.addTag("RB_Dispenser")
  o.addTag("RB_Board")
  o.setGMNotes(JSON.encode({ p = pos, r = rot or { 0, 0, 0 } }))
end

function refillDispenser(obj, pickerColor)
  local ok, home = pcall(JSON.decode, obj.getGMNotes())
  if not ok or type(home) ~= "table" or not home.p then return end
  local data = obj.getData()
  -- never stack a second pile item on the same spot
  local occupied = false
  for _, h in ipairs(Physics.cast({ origin = { home.p[1], surfaceY + 6, home.p[3] }, direction = { 0, -1, 0 },
      type = 3, size = { 1.2, 1, 1.2 }, max_distance = 10 })) do
    local o = h.hit_object
    if o and o ~= obj and o.hasTag and o.hasTag("RB_Dispenser") then occupied = true end
  end
  obj.removeTag("RB_Dispenser")
  obj.removeTag("RB_Board")
  obj.removeTag("RB_TokenDisplay")
  obj.setGMNotes("")
  if obj.type == "Card" and pickerColor and isSeat(pickerColor) then obj.addTag("RB_" .. pickerColor) end
  if occupied then return end
  spawnObjectData({
    data = data, position = home.p, rotation = home.r,
    callback_function = function(n)
      n.setPosition(home.p)
      n.setRotation(home.r)
      if n.hasTag("RB_Marker") then labelMarker(n) end
    end,
  })
end

DISPENSER_ITEMS = {}
for _, k in ipairs(MARKER_ORDER) do DISPENSER_ITEMS[#DISPENSER_ITEMS + 1] = { marker = k } end
DISPENSER_ITEMS[#DISPENSER_ITEMS + 1] = { obj = "Die_6", name = "Dice (d6)" }
DISPENSER_ITEMS[#DISPENSER_ITEMS + 1] = { obj = "Die_20", name = "Dice (d20)" }

-- Grid of markers + dice around (cx, cz), 4 columns, readable from the south
function spawnMarkerSupply(cx, cz, rotY)
  rotY = rotY or 0
  local sg = (rotY == 180) and -1 or 1          -- mirror the grid for the far side
  local cols, dx, dz = 4, 2.3, 2.3
  for i, it in ipairs(DISPENSER_ITEMS) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local pos = { cx + sg * (col - (cols - 1) / 2) * dx, surfaceY + 0.4, cz - sg * (row - 1) * dz }
    local rot = { 0, rotY, 0 }
    if it.marker then
      spawnMarkerObj(it.marker, pos, function(o) makeDispenser(o, pos, rot) end, rotY)
    else
      spawnObject({
        type = it.obj, position = pos, rotation = rot, scale = { 0.8, 0.8, 0.8 }, sound = false,
        callback_function = function(d)
          d.setName(it.name)
          d.addTag("RB_Dice")
          makeDispenser(d, pos, rot)
        end,
      })
    end
  end
  spawnLabel("MARKERS & DICE", { cx, surfaceY + 0.05, cz + sg * 3.9 }, rotY, 22, { 0.75, 0.7, 0.6 })
end

function supplySpots()
  if state.mode == "Duel" then
    return { markers = { { -30.5, -9, 0 }, { 30.5, 13, 180 } }, tokens = { -30.5, 11 } }
  end
  return { markers = { { -34.5, -34.5, 0 }, { 34.5, 34.5, 180 } }, tokens = { -34.5, 34.5 } }
end

function spawnTokenTrays()
  for _, p in ipairs(supplySpots().markers) do spawnMarkerSupply(p[1], p[2], p[3]) end
end

-- The game's token cards (Recruit, Sprite, Gold, ...) from the official data:
-- one face-up card with arrows to flip through them; drag it out to use it,
-- a fresh copy stays behind.
tokenList, tokenIdx = {}, 1
tokenGen, tokenBuilding = 0, false

function spawnTokenDisplay()
  tokenGen = tokenGen + 1
  local gen = tokenGen
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_TokenDisplay") and o.hasTag("RB_Dispenser") then o.destruct() end
  end
  local info = tokenList[tokenIdx]
  if not info then return end
  local spot = supplySpots().tokens
  local pos = { spot[1], surfaceY + 0.5, spot[2] }
  local rot = { 0, 180, 0 }
  local data = (cardData(info, "Table"))
  data.Transform.posX, data.Transform.posY, data.Transform.posZ = pos[1], pos[2], pos[3]
  data.Transform.rotY = 180
  table.insert(data.Tags, "RB_TokenDisplay")
  spawnObjectData({
    data = data, position = pos, rotation = rot,
    callback_function = function(o)
      -- a newer display was requested meanwhile: drop this one
      if gen ~= tokenGen then o.destruct(); return end
      makeDispenser(o, pos, rot)
    end,
  })
  setLabel("tokens:name", info.name .. "  (" .. tokenIdx .. "/" .. #tokenList .. ")")
end

function stepToken(d)
  if #tokenList == 0 then return end
  tokenIdx = ((tokenIdx - 1 + d) % #tokenList) + 1
  spawnTokenDisplay()
end

function spawnTokenCards()
  if backURL() == "" or tokenBuilding then return end
  tokenBuilding = true
  Wait.time(function() tokenBuilding = false end, 5)
  loadOfficial(function(off)
    if not off or not off.tokens then return end
    local seen, list = {}, {}
    for _, t in ipairs(off.tokens) do
      local item = officialItemRange(t)
      if item and item.name and not seen[item.name] and item.media.image_url then
        seen[item.name] = true
        local info = cardInfoFromItem(item, tostring(item.riftbound_id))
        info.type = "Token"
        list[#list + 1] = info
      end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    tokenList = list
    if tokenIdx > #tokenList then tokenIdx = 1 end
    if #tokenList == 0 then return end
    local spot = supplySpots().tokens
    _G["rbt_prev"] = function() stepToken(-1) end
    _G["rbt_next"] = function() stepToken(1) end
    for _, o in ipairs(getObjects()) do
      if o.hasTag("RB_Ctl") and ctl["tokens:prev"] == o then o.destruct() end
    end
    spawnControl("tokens:prev", spot[1] - 3.0, spot[2], 0, "button", btnParams("<", "rbt_prev", 1.6, 1.6, "mini", "Previous token card"))
    spawnControl("tokens:next", spot[1] + 3.0, spot[2], 0, "button", btnParams(">", "rbt_next", 1.6, 1.6, "mini", "Next token card"))
    spawnControl("tokens:name", spot[1], spot[2] - 3.0, 0, "button", btnParams("", nil, 7.0, 0.9, "label"))
    spawnControl("tokens:title", spot[1], spot[2] + 3.0, 0, "button", btnParams("TOKEN CARDS - drag one out", nil, 9.0, 0.8, "muted"))
    Wait.time(spawnTokenDisplay, 1.0)
  end)
end

-- Anything that falls off the table is put back on the nearest table edge
function rescueFallen()
  local w, h = matSize()
  for _, o in ipairs(getObjects()) do
    if not o.getLock() then
      local p = o.getPosition()
      if p.y < surfaceY - 6 then
        local x = math.max(-w / 2 + 3, math.min(w / 2 - 3, p.x))
        local z = math.max(-h / 2 + 3, math.min(h / 2 - 3, p.z))
        o.setVelocity({ 0, 0, 0 })
        o.setAngularVelocity({ 0, 0, 0 })
        o.setPosition({ x, surfaceY + 2, z })
      end
    end
  end
end

function spawnSeatDice()
  for _, color in ipairs(mode().seats) do
    local z = ZONES.dice
    local f = seatFrame(color)
    local dice = { { "Die_6", -0.6, 0.55 }, { "Die_6", 0.6, 0.55 }, { "Die_20", 0, -0.6 } }
    for _, d in ipairs(dice) do
      local p = toWorld(color, z[1] + d[2], z[2] + d[3], 1.0)
      spawnObject({
        type = d[1], position = p, rotation = { 0, f.cardRotY, 0 }, scale = { 0.65, 0.65, 0.65 }, sound = false,
        callback_function = function(o)
          o.setColorTint(COLOR_RGB[color])
          o.addTag("RB_Board")
          o.addTag("RB_Dice")
        end,
      })
    end
  end
end

function placeHands()
  local w = matSize()
  for color, guid in pairs(state.hands) do
    local h = getObjectFromGUID(guid)
    if h then
      local f = seatFrame(color)
      if f then
        local x, z = localToWorld(f, -5.5, f.handZ)
        h.setPosition({ x, 3.6, z })
        h.setRotation({ 0, f.textRotY, 0 })
        h.setScale({ 28, 6, 6 })
      else
        h.setPosition({ w / 2 + 20, 3.6, w / 2 + 20 })
        h.setRotation({ 0, 0, 0 })
        h.setScale({ 8, 4, 4 })
      end
    end
  end
end

-- Second hand zone per seat: cards in it are face up for the owner only
peekZone = {}
function peekCenter(color)
  local f = seatFrame(color)
  local x, z = localToWorld(f, PEEK_U, f.handZ)
  return x, z
end

function spawnPeekZones()
  peekZone = {}
  for _, color in ipairs(mode().seats) do
    local f = seatFrame(color)
    local x, z = peekCenter(color)
    spawnObjectData({
      data = {
        Name = "HandTrigger", FogColor = color, Locked = true,
        Transform = { posX = x, posY = 3.6, posZ = z, rotX = 0, rotY = f.textRotY, rotZ = 0,
                      scaleX = PEEK_W, scaleY = 6, scaleZ = 6 },
        Tags = { "RB_Board", "RB_PeekZone" },
      },
      position = { x, 3.6, z }, rotation = { 0, f.textRotY, 0 },
      callback_function = function(o) peekZone[color] = o end,
    })
  end
end

function buildBoard()
  if boardBuilding then return end
  boardBuilding = true
  Global.setVectorLines({})
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_Board") then o.destruct() end
  end
  ctl = {}
  spawnTable()
  Wait.time(function()
    measureSurface()
    placeHands()
    spawnSeatMats()
    spawnBfMats()
    spawnLabels()
    spawnTokenTrays()
    spawnSeatDice()
    drawZones()
    setSnaps()
    buildControls()
    state.boardVersion = BOARD_VERSION
    boardBuilding = false
  end, 1.0)
end

------------------------------------------------------------------------
-- IN-WORLD CONTROLS
-- Every control sits on its own hidden anchor (a block sunk into the table
-- top), so placement never depends on TTS button offsets.
------------------------------------------------------------------------

TABLE_RGB = { 0.075, 0.09, 0.115 }

STYLE = {
  normal  = { bg = { 0.11, 0.14, 0.19 }, fg = { 0.91, 0.89, 0.85 }, hover = { 0.17, 0.21, 0.27 }, press = { 0.08, 0.10, 0.13 }, k = 0.40 },
  primary = { bg = { 0.84, 0.70, 0.42 }, fg = { 0.09, 0.07, 0.04 }, hover = { 0.90, 0.77, 0.50 }, press = { 0.74, 0.60, 0.33 }, k = 0.40 },
  label   = { bg = TABLE_RGB, fg = { 0.91, 0.89, 0.85 }, hover = TABLE_RGB, press = TABLE_RGB, k = 0.40 },
  big     = { bg = TABLE_RGB, fg = { 0.96, 0.94, 0.88 }, hover = TABLE_RGB, press = TABLE_RGB, k = 0.62 },
  muted   = { bg = TABLE_RGB, fg = { 0.62, 0.66, 0.71 }, hover = TABLE_RGB, press = TABLE_RGB, k = 0.40 },
  mini    = { bg = { 0.15, 0.18, 0.23 }, fg = { 0.85, 0.88, 0.92 }, hover = { 0.22, 0.26, 0.32 }, press = { 0.10, 0.12, 0.16 }, k = 0.55 },
}

function rb_noop() end

function btnParams(label, fn, w, h, style, tip)
  local s = STYLE[style or "normal"]
  return {
    click_function = fn or "rb_noop", function_owner = Global, label = label,
    width = math.floor(w * BTN_UNITS), height = math.floor(h * BTN_UNITS),
    font_size = math.floor(h * BTN_UNITS * s.k),
    color = s.bg, font_color = s.fg, hover_color = s.hover, press_color = s.press,
    tooltip = tip or "",
  }
end

function inputParams(placeholder, fn, w, h, value)
  return {
    input_function = fn, function_owner = Global, label = placeholder,
    width = math.floor(w * BTN_UNITS), height = math.floor(h * BTN_UNITS),
    font_size = math.floor(h * BTN_UNITS * 0.36),
    color = { 0.04, 0.055, 0.075 }, font_color = { 0.91, 0.89, 0.85 },
    alignment = 2, value = value or "",
  }
end

function spawnControl(key, x, z, rotY, kind, params)
  spawnObject({
    type = "BlockSquare", position = { x, surfaceY - 0.55, z },
    rotation = { 0, rotY + BTN_ROT_OFFSET, 0 }, scale = { 1, 1, 1 }, sound = false,
    callback_function = function(o)
      o.setLock(true)
      o.setColorTint({ 0.075, 0.09, 0.115 })
      o.addTag("RB_Board")
      o.addTag("RB_Ctl")
      params.position = { 0, 0.62, 0 }
      if kind == "input" then o.createInput(params) else o.createButton(params) end
      ctl[key] = o
    end,
  })
end

-- Per-seat click handlers are generated so one function knows its seat
function seatFn(action, color)
  local name = "rbc_" .. action .. "_" .. color
  _G[name] = function(obj, pc, alt) seatAction(action, color, pc, alt) end
  return name
end

function seatInputFn(color)
  local name = "rbi_deck_" .. color
  _G[name] = function(obj, pc, value, selected) inputs[color] = value end
  return name
end

-- u, row (+1 toward the mat, -1 toward the player), width, label, action, style, tooltip
SEAT_CONTROLS = {
  { "sit",     -19.8,  1, 5.8,  "Sit here",      "sit",     "primary", "Take this seat" },
  { "deck",    -11.2,  1, 10.4, nil,             nil,       nil,       nil },
  { "deckClear", -5.2,  1, 1.0,  "X",             "deckClear", "mini",  "Clear the deck code" },
  { "import",   -2.6,  1, 3.6,  "Import",        "import",  "primary", "Import the deck code" },
  { "draw",      1.3,  1, 3.4,  "Draw 1",        "draw",    "normal",  "Draw a card" },
  { "channel",   5.0,  1, 3.4,  "Channel 1",     "channel", "normal",  "Channel one rune" },
  { "next",      8.9,  1, 3.6,  "Next phase",    "next",    "normal",  "Run the next phase (manual mode)" },
  { "ptsMinus", 13.0,  1, 1.3,  "-",             "ptsMinus","mini",    "Remove a point" },
  { "pts",      16.3,  1, 4.4,  "0 / 8",         nil,       "big",     "Points (first to the victory score wins)" },
  { "ptsPlus",  19.6,  1, 1.3,  "+",             "ptsPlus", "mini",    "Add a point" },
  { "status",  -17.8, -1, 10.0, "",              nil,       "label",   nil },
  { "peek",    -11.0, -1, 3.0,  "Peek",          "peek",    "normal",  "Look at the top card of your deck (right-click: top 3)" },
  { "reveal",   -7.7, -1, 3.0,  "Reveal",        "reveal",  "normal",  "Reveal the top card of your deck to everyone (right-click: top 3)" },
  { "mull",     -4.0, -1, 3.8,  "Mulligan done", "mull",    "normal",  "Cards on your Base are set aside, redrawn and recycled" },
  { "ready",    -0.3, -1, 3.0,  "Ready all",     "ready",   "normal",  "Ready all your cards" },
  { "shuffle",   3.0, -1, 3.0,  "Shuffle",       "shuffle", "normal",  "Shuffle your main deck" },
  { "burn",      6.3, -1, 3.0,  "Burn out",      "burn",    "normal",  "Shuffle trash into deck, an opponent gains 1 point" },
  { "endturn",   9.45,-1, 3.0,  "End turn",      "endturn", "normal",  "End your turn" },
  { "xpMinus",  13.0, -1, 1.3,  "-",             "xpMinus", "mini",    "Spend XP" },
  { "xp",       16.3, -1, 4.4,  "XP 0",          nil,       "muted",   "Experience" },
  { "xpPlus",   19.6, -1, 1.3,  "+",             "xpPlus",  "mini",    "Gain XP" },
  { "clear",    22.0, -1, 1.6,  "Clear",         "clear",   "mini",   "Remove all your cards from the table" },
}
ROW_DZ, ROW_H = 0.85, 1.3

function buildSeatControls(color)
  local f = seatFrame(color)
  for _, c in ipairs(SEAT_CONTROLS) do
    local key, u, row, w = c[1], c[2], c[3], c[4]
    -- Next phase only matters when the host turned automatic phases off
    local show = not (key == "next" and state.autoPhases)
    if show then
      local x, z = consoleXZ(color, u, row * ROW_DZ)
      if key == "deck" then
        spawnControl(color .. ":deck", x, z, f.textRotY, "input",
          inputParams("Paste Piltover Archive deck code", seatInputFn(color), w, ROW_H, inputs[color]))
      else
        local fn = c[6] and seatFn(c[6], color) or "rb_noop"
        spawnControl(color .. ":" .. key, x, z, f.textRotY, "button", btnParams(c[5], fn, w, ROW_H, c[7], c[8]))
      end
    end
  end
end

-- Host console: Duel -> east margin; four-player -> south-east corner
function hostOrigin()
  if state.mode == "Duel" then return 31, 0 end
  return 34.5, -34.5
end

function hostFn(name, fn) _G[name] = fn; return name end

function buildHostControls()
  local ox, oz = hostOrigin()
  local function at(u, v) return ox + u, oz + v end
  local function hbtn(key, u, v, w, h, label, fn, style, tip)
    local x, z = at(u, v)
    spawnControl("host:" .. key, x, z, 0, "button", btnParams(label, fn, w, h, style, tip))
  end
  local function hinput(key, u, v, placeholder, fn, value)
    local x, z = at(u - 0.6, v)
    spawnControl("host:" .. key, x, z, 0, "input", inputParams(placeholder, fn, 10.4, 0.95, value))
    hbtn(key .. "Clear", 5.3, v, 1.0, 0.95, "X",
      hostFn("rbh_clear_" .. key, function(_, pc) hostClearAsset(pc, key) end), "mini", "Clear this link")
  end

  hbtn("title", 0, 5.4, 11.6, 1.0, "TABLE  -  HOST", nil, "label")
  for i, k in ipairs(MODE_ORDER) do
    hbtn("mode_" .. k, -4.35 + (i - 1) * 2.9, 4.2, 2.7, 1.0, MODES[k].label,
      hostFn("rbh_mode_" .. k, function(_, pc) hostMode(pc, k) end),
      (k == state.mode) and "primary" or "normal", "Switch to " .. MODES[k].label)
  end
  hbtn("startLabel", 0, 3.0, 11.6, 0.8, "START GAME  -  WHO GOES FIRST", nil, "muted")
  local firsts = { "Random" }
  for _, c in ipairs(mode().seats) do firsts[#firsts + 1] = c end
  local bw = 11.6 / #firsts
  for i, c in ipairs(firsts) do
    hbtn("start_" .. c, -5.8 + bw * (i - 0.5), 2.0, bw - 0.2, 1.0, c,
      hostFn("rbh_start_" .. c, function(_, pc) hostStart(pc, c) end),
      (c == "Random") and "primary" or "normal", "Start a new game")
  end
  hbtn("skip",  -3.9, 0.7, 3.7, 1.0, "Skip mulligan", hostFn("rbh_skip", function(_, pc) hostSkip(pc) end), "normal")
  hbtn("reset",  0.0, 0.7, 3.7, 1.0, "Reset scores",  hostFn("rbh_reset", function(_, pc) hostReset(pc) end), "normal")
  hbtn("auto",   3.9, 0.7, 3.7, 1.0, "Auto: On",      hostFn("rbh_auto", function(_, pc) hostAuto(pc) end), "normal",
    "Run turn phases automatically")
  hbtn("rotate", -2.95, -0.5, 5.7, 1.0, "Rotate mats", hostFn("rbh_rotate", function(_, pc) hostRotate(pc) end), "normal")
  hbtn("rebuild", 2.95, -0.5, 5.7, 1.0, "Rebuild table", hostFn("rbh_rebuild", function(_, pc) hostRebuild(pc) end), "normal")
  hbtn("backLabel", 0, -1.6, 11.6, 0.7, "CARD BACK LINK - paste, then click elsewhere", nil, "muted")
  hinput("back", 0, -2.45, "Card back image link (required)", hostFn("rbh_in_back",
    function(_, pc, v, sel) hostAsset(pc, "back", v, sel) end), state.back)
  hbtn("matLabel", 0, -3.4, 11.6, 0.7, "PLAYMAT IMAGE LINK", nil, "muted")
  hinput("mat", 0, -4.25, "Playmat image link (optional)", hostFn("rbh_in_mat",
    function(_, pc, v, sel) hostAsset(pc, "mat", v, sel) end), state.mat)
  hbtn("bfLabel", 0, -5.2, 11.6, 0.7, "BATTLEFIELD MAT IMAGE LINK", nil, "muted")
  hinput("bf", 0, -6.05, "Battlefield mat image link (optional)", hostFn("rbh_in_bf",
    function(_, pc, v, sel) hostAsset(pc, "bfMat", v, sel) end), state.bfMat)
  hbtn("bug", -4.0, -7.25, 3.6, 0.95, "Report a bug", hostFn("rbh_bug", function(_, pc) reportBug(pc) end),
    "primary", "Show where to report bugs")
  local bx, bz = at(1.85, -7.25)
  spawnControl("host:bugUrl", bx, bz, 0, "input", inputParams(ISSUES_URL, hostFn("rbh_bugurl",
    function(o, pc, v, sel) keepBugUrl(o, v, sel) end), 7.7, 0.95, ISSUES_URL))
  hbtn("credit", 0, -8.2, 11.6, 0.7, MOD_NAME .. " v" .. MOD_VERSION ..
    " - not endorsed by Riot Games", nil, "muted", DISCLAIMER)
end

-- Bug reports: TTS can't open a browser from a script, so the link is shown
-- in chat and in a field on the host console that anyone can copy from.
function reportBug(pc)
  printToColor("Report a bug: " .. ISSUES_URL, pc, GOLD)
  printToColor("Copy the link from the field next to the button (click it, Ctrl+A, Ctrl+C). " ..
    "Please include your deck code, the mode, and any chat line starting with [Riftbound].", pc, { 0.8, 0.8, 0.8 })
end

function keepBugUrl(o, value, selected)
  if selected or value == ISSUES_URL then return end
  Wait.frames(function()
    if o ~= nil then pcall(function() o.editInput({ index = 0, value = ISSUES_URL }) end) end
  end, 1)
end

controlsBuilding = false
function buildControls()
  if controlsBuilding then return end
  controlsBuilding = true
  Wait.time(function() controlsBuilding = false end, 2.5)
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_Ctl") then o.destruct() end
  end
  ctl = {}
  for _, c in ipairs(mode().seats) do buildSeatControls(c) end
  buildHostControls()
  Wait.time(spawnTokenCards, 1.0)
  Wait.time(refreshControls, 1.5)
end

function setLabel(key, label, style)
  local o = ctl[key]
  if o == nil then return end
  local p = { index = 0, label = label }
  if style then
    local s = STYLE[style]
    p.color, p.font_color, p.hover_color, p.press_color = s.bg, s.fg, s.hover, s.press
  end
  pcall(function() o.editButton(p) end)
end

function shortName(color)
  local p = Player[color]
  if p and p.seated then
    local n = p.steam_name or color
    if #n > 14 then n = n:sub(1, 13) .. "." end
    return n
  end
  return nil
end

function seatStatus(color)
  local g = state.game
  if not g then
    if findPileAt(zonePos(color, "mainDeck")) then return "Deck ready - waiting for host" end
    return "Paste deck code, press Import"
  end
  if g.phase == "Setup" or g.phase == "Mulligan" then
    if g.mulligan[color] then return "Waiting for other mulligans" end
    return "Mulligan: up to 2 cards to Base"
  end
  local cur = currentPlayer()
  if cur == color then return "YOUR TURN  -  " .. g.phase:upper() end
  return cur:upper() .. "'S TURN  -  " .. g.phase:upper()
end

function refreshControls()
  local g = state.game
  local active = g and g.turn and g.turn > 0 and currentPlayer() or nil
  for _, c in ipairs(mode().seats) do
    local name = shortName(c)
    setLabel(c .. ":sit", name or "Sit here", name and "label" or "primary")
    setLabel(c .. ":pts", tostring(state.points[scoreKey(c)] or 0) .. " / " .. mode().victory)
    setLabel(c .. ":xp", "XP " .. tostring(state.xp[c] or 0))
    setLabel(c .. ":status", seatStatus(c))
    setLabel(c .. ":endturn", "End turn", (c == active) and "primary" or "normal")
  end
  setLabel("host:auto", state.autoPhases and "Auto: On" or "Auto: Off")
end

refreshScore = function() refreshControls() end

-- Seat actions ---------------------------------------------------------

function sitAt(color, pc)
  local p = Player[color]
  if pc == color then
    broadcastToColor("You're already sitting here.", pc, { 0.8, 0.8, 0.8 })
  elseif p and p.seated then
    broadcastToColor(color .. " is taken by " .. (p.steam_name or "someone") .. ".", pc, { 1, 0.6, 0.4 })
  else
    Player[pc].changeColor(color)
  end
end

function seatAction(action, color, pc, alt)
  if action == "sit" then sitAt(color, pc); return end
  local isHost = Player[pc] and Player[pc].host
  if pc ~= color and not isHost then
    broadcastToColor("These are " .. color .. "'s controls.", pc, { 1, 0.6, 0.4 })
    return
  end
  if action == "deckClear" then
    inputs[color] = ""
    local o = ctl[color .. ":deck"]
    if o then pcall(function() o.editInput({ index = 0, value = "" }) end) end
  elseif action == "import" then
    local text = inputs[color]
    if (text == nil or text == "") and ctl[color .. ":deck"] then
      local ins = ctl[color .. ":deck"].getInputs()
      if ins and ins[1] then text = ins[1].value end
    end
    importDeck(color, text)
  elseif action == "peek" then peekCards(color, alt and 3 or 1)
  elseif action == "reveal" then revealCards(color, alt and 3 or 1)
  elseif action == "draw" then drawCards(color, 1)
  elseif action == "channel" then channelRunes(color, 1)
  elseif action == "next" then
    if state.game and (currentPlayer() == color or isHost) then nextPhase(color) end
  elseif action == "mull" then mulliganDone(color)
  elseif action == "ready" then readyAll(color)
  elseif action == "shuffle" then shuffleMain(color)
  elseif action == "burn" then burnOut(color)
  elseif action == "endturn" then
    local g = state.game
    if g and g.turn > 0 and (currentPlayer() == color or isHost) then endTurn(color)
    elseif g and g.turn > 0 then broadcastToColor("It's not your turn.", pc, { 1, 0.6, 0.4 }) end
  elseif action == "clear" then
    clearArea(color)
    broadcastToAll(color .. " cleared their cards.", COLOR_RGB[color])
    refreshControls()
  elseif action == "ptsPlus" then addPoints(scoreKey(color), 1)
  elseif action == "ptsMinus" then addPoints(scoreKey(color), -1)
  elseif action == "xpPlus" then addXP(color, 1)
  elseif action == "xpMinus" then addXP(color, -1)
  end
end

-- Host actions ---------------------------------------------------------

function isHostColor(pc)
  if Player[pc] and Player[pc].host then return true end
  broadcastToColor("Only the host can use the table console.", pc, { 1, 0.5, 0.4 })
  return false
end

function hostMode(pc, k)
  if not isHostColor(pc) or k == state.mode or not MODES[k] then return end
  for _, c in ipairs({ "Red", "Blue", "Yellow", "Green" }) do clearArea(c) end
  state.mode = k
  resetGame()
  buildBoard()
  broadcastToAll("Mode: " .. mode().label .. ". Seats: " .. table.concat(mode().seats, ", ") .. ".", GOLD)
end

function hostStart(pc, c)
  if not isHostColor(pc) then return end
  startGame(pc, c ~= "Random" and c or nil)
end

function hostSkip(pc)
  if not isHostColor(pc) then return end
  local g = state.game
  if g and (g.phase == "Mulligan" or g.phase == "Setup") then
    for _, c in ipairs(g.order) do g.mulligan[c] = true end
    beginFirstTurn()
  end
end

function hostReset(pc)
  if not isHostColor(pc) then return end
  resetGame()
  broadcastToAll("Scores and turn tracker reset.", GOLD)
end

function hostAuto(pc)
  if not isHostColor(pc) then return end
  state.autoPhases = not state.autoPhases
  buildControls()
  broadcastToAll(state.autoPhases and "Turn phases run automatically." or
    "Manual phases: each player steps through their turn with Next phase.", GOLD)
end

function hostRotate(pc)
  if not isHostColor(pc) then return end
  state.matFlip = not state.matFlip
  buildBoard()
end

function hostRebuild(pc)
  if not isHostColor(pc) then return end
  buildBoard()
end

ASSET_FIELD = { back = "back", mat = "mat", bf = "bfMat" }

function hostClearAsset(pc, key)
  if not isHostColor(pc) then return end
  local field = ASSET_FIELD[key]
  local o = ctl["host:" .. key]
  if o then pcall(function() o.editInput({ index = 0, value = "" }) end) end
  pendingAsset[field] = ""
  if state[field] ~= "" then
    state[field] = ""
    broadcastToColor("Link cleared." .. (key ~= "back" and " Press Rebuild table to remove the image." or ""), pc, { 0.8, 0.8, 0.8 })
  end
end

pendingAsset = {}
function hostAsset(pc, field, value, selected)
  if not (Player[pc] and Player[pc].host) then return end
  pendingAsset[field] = trim(value)
  if selected then return end
  local v = pendingAsset[field]
  if v ~= "" and not v:match("^https?://") and not v:match("^file:") then
    broadcastToColor("That doesn't look like a link.", pc, { 1, 0.5, 0.4 })
    return
  end
  if state[field] == v then return end
  state[field] = v
  if field == "back" then
    broadcastToColor("Card back saved. New imports use it.", pc, { 0.7, 0.9, 0.7 })
  else
    broadcastToColor("Image saved. Press Rebuild table to apply it.", pc, { 0.7, 0.9, 0.7 })
  end
end

------------------------------------------------------------------------
-- TTS TURN SYSTEM
-- Uses TTS's own turn indicator when every seat is taken.
------------------------------------------------------------------------

function allSeated()
  for _, c in ipairs(mode().seats) do
    if not (Player[c] and Player[c].seated) then return false end
  end
  return true
end

function syncTurns()
  local g = state.game
  if not g or not g.turn or g.turn == 0 then
    Turns.enable = false
    return
  end
  if not allSeated() then return end
  Turns.type = 2
  Turns.order = g.order
  Turns.enable = true
  if Turns.turn_color ~= currentPlayer() then Turns.turn_color = currentPlayer() end
end

-- A player passed the turn with TTS's own turn controls
function onPlayerTurn(player, previous)
  local g = state.game
  if not g or not g.turn or g.turn == 0 or not player then return end
  local c = player.color
  if c == currentPlayer() then return end
  local idx
  for i, oc in ipairs(g.order) do if oc == c then idx = i end end
  if not idx then return end
  g.firstTurnDone[currentPlayer()] = true
  for _, o in ipairs(getObjects()) do
    if o.hasTag("RB_Damage") then o.destruct() end
  end
  g.turnIdx = idx
  g.turn = g.turn + 1
  startTurn()
end

function onPlayerChangeColor(color)
  Wait.frames(refreshControls, 5)
end

-- Kept for chat commands
function rbNext(player)
  if not state.game then return end
  if player.host or player.color == currentPlayer() then nextPhase(player.color)
  else broadcastToColor("It's not your turn.", player.color, { 1, 0.6, 0.4 }) end
end

function rbEndTurn(player)
  local g = state.game
  if not g or g.turn == 0 then return end
  if player.host or player.color == currentPlayer() then endTurn(player.color)
  else broadcastToColor("It's not your turn.", player.color, { 1, 0.6, 0.4 }) end
end

------------------------------------------------------------------------
-- CHAT COMMANDS
------------------------------------------------------------------------

function onChat(message, player)
  local raw, rest = message:match("^!rb%s+(%S+)%s*(.*)$")
  if not raw then return end
  local cmd = raw:lower()
  local n = tonumber(rest)
  local c = player.color
  if cmd == "help" then
    printToColor("!rb <deck code> | draw [n] | channel [n] | peek [n] | reveal [n] | ready | shuffle | burnout | mulligan | token <name> | next | end | clear | bug", c, GOLD)
  elseif cmd == "bug" or cmd == "about" then
    printToColor(MOD_NAME .. " v" .. MOD_VERSION .. "  -  " .. REPO_URL, c, GOLD)
    reportBug(c)
    printToColor(DISCLAIMER, c, { 0.62, 0.66, 0.71 })
  elseif cmd == "test" then
    local code = trim(rest ~= "" and rest or "OGN-007")
    local p = parseCode(code)
    if not p then printToColor("Not a card code: " .. code, c, { 1, 0.5, 0.4 }); return false end
    local url = API_BASE .. "/cards/riftbound/" .. lookupQuery(p)
    printToColor("Testing " .. url, c, { 0.8, 0.8, 0.8 })
    httpJSON(url, function(data, err)
      if not data then printToColor("FAILED: " .. tostring(err), c, { 1, 0.4, 0.4 }); return end
      local items = data.items or data
      printToColor("OK: " .. #items .. " result(s)", c, { 0.6, 0.9, 0.6 })
      for i, it in ipairs(items) do
        if i > 3 then break end
        printToColor(tostring(it.riftbound_id) .. "  " .. tostring(it.name) .. "  " ..
          tostring(it.media and it.media.image_url), c, { 0.8, 0.85, 0.9 })
      end
    end)
  elseif not isSeat(c) then
    broadcastToColor("Sit at " .. table.concat(mode().seats, " / ") .. " first.", c, { 1, 0.4, 0.4 })
  elseif cmd == "draw" then drawCards(c, n or 1)
  elseif cmd == "channel" then channelRunes(c, n or 1)
  elseif cmd == "peek" then peekCards(c, n or 1)
  elseif cmd == "reveal" then revealCards(c, n or 1)
  elseif cmd == "ready" then readyAll(c)
  elseif cmd == "shuffle" then shuffleMain(c)
  elseif cmd == "burnout" then burnOut(c)
  elseif cmd == "mulligan" then mulliganDone(c)
  elseif cmd == "token" then spawnTokenCard(c, rest)
  elseif cmd == "next" then rbNext(player)
  elseif cmd == "end" then rbEndTurn(player)
  elseif cmd == "clear" then clearArea(c)
  else importDeck(c, raw .. " " .. rest) end
  return false
end

------------------------------------------------------------------------
-- LIFECYCLE
------------------------------------------------------------------------

function onSave()
  return JSON.encode(state)
end

function onLoad(saved)
  pcall(function() math.randomseed(os.time()) end)
  local fresh = true
  if saved and saved ~= "" then
    local ok, s = pcall(JSON.decode, saved)
    if ok and type(s) == "table" and s.version == state.version then
      for k, v in pairs(s) do state[k] = v end
      fresh = false
    end
  end
  if not MODES[state.mode] then state.mode = "Duel" end

  UI.setXml("")

  if fresh or state.boardVersion ~= BOARD_VERSION then
    Wait.frames(buildBoard, 5)
  else
    Wait.time(function()
      measureSurface()
      drawZones()
      setSnaps()
      placeHands()
      buildControls()
    end, 0.5)
  end

  for _, o in ipairs(getObjects()) do
    addCardMenu(o)
    if o.hasTag("RB_Marker") then labelMarker(o) end
  end
  Wait.time(rescueFallen, 2, -1)
  print(MOD_NAME .. " v" .. MOD_VERSION .. "  -  sit down with the button on your side of the table. Chat: !rb help  -  bugs: !rb bug")
  print(DISCLAIMER)
end
