fx_version "cerulean"
game "gta5"
lua54 "yes"

name "helicam"
original_author "ZeroFour04"
author "helicam contributors (see README.md for credits)"
description "A FiveM helicopter camera script"
version "1.0.0"

shared_scripts {
    "@ox_lib/init.lua",
    "config.lua",
}

server_scripts {
    "server.lua",
}

client_scripts {
    "client.lua",
}

dependency "ox_lib"
