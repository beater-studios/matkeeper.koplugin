-- Pokémon TCG, as a turn panel: damage, prizes and the Bench stay on the physical table. Values from
-- the official rulebook (Scarlet & Violet era) and the Professor Program update of February 2026.
return {
    id = "pokemon",
    kind = "turn",
    formats = {
        { id = "standard", min = 2, max = 2 },
    },
    -- Things the rules allow once per turn. Cards may allow more, so they are reminders, never locks.
    reminders = { "energy", "supporter", "retreat", "stadium" },
    -- Asleep, Confused and Paralyzed turn the card, so only the last one stays. Burned and Poisoned use
    -- markers and go with any of them.
    exclusive = { "sleep", "confusion", "paralysis" },
    markers = { "burn", "poison" },
    -- Pokémon Checkup resolves the conditions in this order, for both Active Pokémon.
    checkup_order = { "poison", "burn", "sleep", "paralysis" },
    burn_damage = 20,
    poison_damage = 10,
    poison_step = 10,
    poison_max = 200,
}
