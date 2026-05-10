local M = {}

local function rgb(r, g, b)
    return { r / 255, g / 255, b / 255, 1 }
end

M.PLANET_COLORS = {
    ["Metal rich body"]                   = rgb(218, 165,  32),
    ["High metal content body"]           = rgb(170, 170, 178),
    ["Rocky body"]                        = rgb(170, 130,  95),
    ["Rocky ice body"]                    = rgb(180, 200, 220),
    ["Icy body"]                          = rgb(170, 220, 245),
    ["Earthlike body"]                    = rgb(110, 200, 130),
    ["Water world"]                       = rgb( 80, 140, 230),
    ["Water giant"]                       = rgb( 50, 100, 200),
    ["Water giant with life"]             = rgb( 70, 180, 180),
    ["Ammonia world"]                     = rgb(230, 170,  90),
    ["Sudarsky class I gas giant"]        = rgb(230, 210, 160),
    ["Sudarsky class II gas giant"]       = rgb(220, 215, 200),
    ["Sudarsky class III gas giant"]      = rgb(170, 195, 220),
    ["Sudarsky class IV gas giant"]       = rgb(210, 145,  80),
    ["Sudarsky class V gas giant"]        = rgb(140, 145, 155),
    ["Helium gas giant"]                  = rgb(220, 200, 150),
    ["Helium rich gas giant"]             = rgb(225, 195, 130),
    ["Gas giant with ammonia based life"] = rgb(190, 130, 215),
    ["Gas giant with water based life"]   = rgb(120, 200, 175),
}

M.STAR_COLORS = {
    O                     = rgb(155, 175, 255),
    B                     = rgb(170, 200, 255),
    A                     = rgb(220, 230, 255),
    F                     = rgb(255, 245, 220),
    G                     = rgb(255, 230, 130),
    K                     = rgb(255, 180, 110),
    M                     = rgb(255, 130, 110),
    L                     = rgb(190, 100,  90),
    T                     = rgb(150,  80, 110),
    Y                     = rgb(120,  65,  90),
    TTS                   = rgb(255, 200, 130),
    AeBe                  = rgb(180, 210, 255),
    W                     = rgb(150, 175, 255),
    WN                    = rgb(150, 175, 255),
    WC                    = rgb(150, 175, 255),
    WO                    = rgb(150, 175, 255),
    C                     = rgb(220,  80,  50),
    CS                    = rgb(220,  80,  50),
    CN                    = rgb(220,  80,  50),
    CJ                    = rgb(220,  80,  50),
    CH                    = rgb(220,  80,  50),
    CHd                   = rgb(220,  80,  50),
    MS                    = rgb(255, 130, 110),
    S                     = rgb(255, 150, 110),
    DA                    = rgb(240, 245, 255),
    DB                    = rgb(240, 245, 255),
    DC                    = rgb(240, 245, 255),
    DO                    = rgb(240, 245, 255),
    DQ                    = rgb(240, 245, 255),
    DX                    = rgb(240, 245, 255),
    DZ                    = rgb(240, 245, 255),
    N                     = rgb(190, 220, 255),
    H                     = rgb(120,  80, 180),
    X                     = rgb(180, 100, 220),
    SupermassiveBlackHole = rgb( 80,  50, 120),
    A_BlueWhiteSuperGiant = rgb(220, 230, 255),
    B_BlueWhiteSuperGiant = rgb(170, 200, 255),
    F_WhiteSuperGiant     = rgb(255, 245, 220),
    G_WhiteSuperGiant     = rgb(255, 230, 130),
    K_OrangeGiant         = rgb(255, 180, 110),
    M_RedGiant            = rgb(255, 130, 110),
    M_RedSuperGiant       = rgb(255, 100,  90),
}

M.BODY_TYPE_COLORS = {}
for body_type, color in pairs(M.PLANET_COLORS) do
    M.BODY_TYPE_COLORS[body_type] = color
end
for body_type, color in pairs(M.STAR_COLORS) do
    M.BODY_TYPE_COLORS[body_type] = color
end

function M.lookup(body_type)
    if not body_type or body_type == "" then return nil end
    return M.BODY_TYPE_COLORS[body_type]
end

return M
