-- Park-Miller minimal standard generator: exact in doubles, so tests can repeat a sequence from a seed.
local Rng = {}
Rng.__index = Rng

local MODULUS = 2147483647
local MULTIPLIER = 16807

function Rng.new(seed)
    local state = math.floor(tonumber(seed) or 1) % MODULUS
    if state <= 0 then
        state = state + MODULUS - 1
    end
    local rng = setmetatable({ state = state }, Rng)
    for _ = 1, 3 do
        rng:next()
    end
    return rng
end

-- A seed for real games, mixing the clock with the time the process has been running.
function Rng.fresh()
    return Rng.new(os.time() * 1000 + math.floor((os.clock() * 1e6) % 1000))
end

function Rng:next()
    self.state = (self.state * MULTIPLIER) % MODULUS
    return self.state
end

function Rng:int(low, high)
    return low + self:next() % (high - low + 1)
end

function Rng:coin()
    return self:int(0, 1) == 0 and "heads" or "tails"
end

return Rng
