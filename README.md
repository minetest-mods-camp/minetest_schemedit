# Schematic Editor [`schemedit`]

## Version
1.3.0

## Description
This is a mod which allows you to edit and export schematics (`.mts` files).

This mod works in Minetest 5.0.0 or later, but recommended is version 5.1.0
or later.

It supports node probabilities, forced node placement and slice probabilities.

It adds 3 items:

* Schematic Creator: Used to mark a region and export or import it as schematic
* Schematic Void: Marks a position in a schematic which should not replace anything when placed as a schematic
* Schematic Node Probability Tool: Set per-node probabilities and forced node placement

Note: The import feature requires Minetest 5.1.0 or later.

It also adds these server commands:

* `placeschem` to place a schematic
* `mts2lua` to convert .mts files to .lua files (Lua code)

There's also a setting `schemedit_export_lua` to enable automatic export to .lua files.

## Usage help
Usage help can be found when you use the optional Help modpack (mods `doc` and `doc_items`).
The “server” privilege is required for most features.

You should also refer to the Minetest Lua API documentation to understand more about schematics.

## License of everything
MIT License
