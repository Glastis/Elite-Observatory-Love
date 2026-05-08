-- One-stop import for the UI library. `require "observatory.ui"` gives you
-- a table with every primitive — handy in views that compose many of them.

return {
    theme           = require("observatory.ui.theme"),
    input           = require("observatory.ui.input"),
    animation       = require("observatory.ui.animation"),
    text            = require("observatory.ui.text"),
    icon            = require("observatory.ui.icon"),

    panel           = require("observatory.ui.panel"),
    row             = require("observatory.ui.row"),
    button          = require("observatory.ui.button"),
    seg             = require("observatory.ui.seg"),
    tabs            = require("observatory.ui.tabs"),
    checkbox        = require("observatory.ui.checkbox"),
    switch          = require("observatory.ui.switch"),
    section_header  = require("observatory.ui.section_header"),
    labeled_value   = require("observatory.ui.labeled_value"),
    status_cell     = require("observatory.ui.status_cell"),
    pulse           = require("observatory.ui.pulse"),
    list_item       = require("observatory.ui.list_item"),
    code_box        = require("observatory.ui.code_box"),
    text_field      = require("observatory.ui.text_field"),
    grid            = require("observatory.ui.grid"),
}
