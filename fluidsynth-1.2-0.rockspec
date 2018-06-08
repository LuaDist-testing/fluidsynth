-- This file was automatically generated for the LuaDist project.

package = "fluidsynth"
version = "1.2-0"
-- LuaDist source
source = {
  tag = "1.2-0",
  url = "git://github.com/LuaDist-testing/fluidsynth.git"
}
-- Original source
-- source = {
--    url = "http://www.pjb.com.au/comp/lua/fluidsynth-1.2.tar.gz",
--    md5 = "6790285c3b7fdb8e8b5f36b5e7ae2675"
-- }
description = {
   summary = "Interface to the fluidsynth library",
   detailed = [[
      This Lua module offers a calling interface to the Fluidsynth
      library, which uses SoundFonts to synthesise audio.
   ]],
   homepage = "http://www.pjb.com.au/comp/lua/fluidsynth.html",
   license = "MIT/X11",
}
-- http://www.luarocks.org/en/Rockspec_format
dependencies = {
   "lua >=5.1, <5.3",
}
build = {
   type = "builtin",
   modules = {
      ["fluidsynth"] = "fluidsynth.lua",
      ["C-fluidsynth"] = {
         sources   = { "C-fluidsynth.c" },
         libraries = { "fluidsynth" },
      },
   },
   copy_directories = { "doc", "test" },
}