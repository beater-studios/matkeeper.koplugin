-- Magic: The Gathering. Values from the Comprehensive Rules of 2026-11-06 (rule numbers beside them).
return {
    id = "magic",
    kind = "score",
    formats = {
        -- 103.4: everyone starts at 20.
        { id = "standard", min = 2, max = 2, life = 20, poison = 10 },
        -- 103.4c, 903.10a: 40 life, 21 combat damage from the same commander, partners apart (702.124d).
        { id = "commander", min = 2, max = 6, life = 40, poison = 10, commander_damage = 21, tax = true },
        -- 810.4, 810.8d: teams share 30 life and lose with 15 poison.
        { id = "two_headed_giant", min = 2, max = 2, life = 30, poison = 15, teams = true },
        -- 903.12f, 903.12h: 25 life for two, 30 for more, tax but no commander damage.
        { id = "brawl", min = 2, max = 4, life = 25, life_multiplayer = 30, poison = 10, tax = true },
        -- The players set the rules themselves (Match.custom_format).
        { id = "custom", min = 2, max = 6, life = 20, poison = 10, custom = true },
    },
    -- Counters a player can turn on; each shows only while it is above zero.
    counters = { "poison", "energy", "experience", "rad" },
    dice = { 6, 20 },
}
