#!/usr/bin/lua
---------------------------------------------------------------------
--     This Lua5 script is Copyright (c) 2014, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This script is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------
local Version = '1.0  for Lua5'
local VersionDate  = '13aug2014';
local Synopsis = [[
program_name [options] [filenames]
]]
local Midifile = 'folkdance.mid'
local Soundfont = 'Chaos4m.sf2'

local iarg=1; while arg[iarg] ~= nil do
	if string.sub(arg[iarg],1,1) ~= "-" then break end
	local first_letter = string.sub(arg[iarg],2,2)
	if first_letter == 'v' then
		local n = string.gsub(arg[0],"^.*/","",1)
		print(n.." version "..Version.."  "..VersionDate)
		os.exit(0)
	elseif first_letter == 'c' then
		whatever()
	else
		local n = string.gsub(arg[0],"^.*/","",1)
		print(n.." version "..Version.."  "..VersionDate.."\n\n"..Synopsis)
		os.exit(0)
	end
	iarg = iarg+1
end

local FS = require 'fluidsynth'
local parameter2default = FS.default_settings()
print("parameter2default['synth.midi-bank-select'] =",parameter2default['synth.midi-bank-select'])
local settings,msg = FS.new_settings()
print('    settings =',settings)
if not settings then print('settings was nil:',settings,msg) end
print("about to call set('synth.polyphony')")
local rc,msg = FS.set(settings, "synth.polyphony", 128)
if not rc then print(rc, msg) end
print("about to call set('synth.gain')")
rc,msg = FS.set(settings, "synth.gain", 0.8)
if not rc then print(msg) end
print("about to call set('audio.driver')")
rc,msg = FS.set(settings, "audio.driver", "alsa")
if not rc then print(msg) end
-- assert(FS.set(settings, "audio.file.name", "/tmp/t.wav"))
-- assert(FS.set(settings, "audio.file.type", "wav"))
print("about to set an unrecognised parameter")
rc,msg = FS.set(settings, "Sprogthwooklificatig", "why")
if not rc then print(msg) end
print("about to call new_synth")
local synth,msg = FS.new_synth(settings)
if synth == nil then print(msg) end
-- if audio.driver==alsa, could read /proc/asound/devices to help
-- guess best choice for audio.alsa.device (such as: "hw:0", "plughw:1")
print("about to call new_audio_driver")
local audio_driver,msg = FS.new_audio_driver(settings, synth)
if audio_driver == nil then print(msg) end
print("about to call sf_load")
local sf_id,msg = FS.sf_load(synth, Soundfont, 0)
if sf_id == nil then print(msg) end
print("about to call sf_load on non-existent file")
sf_id,msg = FS.sf_load(synth, "/wherever/Zsfuospw9erk.sf2", 0)
if sf_id == nil then print(msg) end

local channel = 0
print("about to call sf_select")
rc,msg = FS.sf_select(synth, channel, sf_id)
if not rc then print(msg) end
print("about to call patch_change")
rc,msg = FS.patch_change(synth, channel, 87)
if not rc then print(msg) end
print("about to call control_change")
rc,msg = FS.control_change(synth, channel, 7, 127) -- cc7=127
if not rc then print(msg) end
print("about to call note_on")
rc,msg = FS.note_on(synth, channel, 60, 100)      -- channel, note, velocity
if not rc then print(msg) end
os.execute('sleep 2')       -- should schedule, or use luaposix...
print("about to call pitch_bend")
rc,msg = FS.pitch_bend(synth, channel, 4000)
if not rc then print(msg) end
os.execute('sleep 2')       -- should schedule, or use luaposix...
print("about to call note_off")
rc,msg = FS.note_off(synth, channel, 60)         -- channel, note
if not rc then print(msg) end
print("about to call pitch_bend")
rc,msg = FS.pitch_bend(synth, channel, 8192)
if not rc then print(msg) end
print("about to call note_on")
rc,msg = FS.note_on(synth, channel, 60, 100)      -- channel, note, velocity
if not rc then print(msg) end
os.execute('sleep 2')       -- should schedule, or use luaposix...
print("about to call pitch_bend")
rc,msg = FS.pitch_bend(synth, channel, 16000)
if not rc then print(msg) end
os.execute('sleep 2')       -- should schedule, or use luaposix...
print("about to call pitch_bend")
rc,msg = FS.pitch_bend(synth, channel, 8192)
if not rc then print(msg) end
os.execute('sleep 2')       -- should schedule, or use luaposix...
print("about to call note_off")
rc,msg = FS.note_off(synth, channel, 60)         -- channel, note
if not rc then print(msg) end
os.execute('sleep 1')       -- should schedule, or use luaposix...

print("about to call delete_audio_driver")
rc,msg = FS.delete_audio_driver(audio_driver)
if not rc then print(msg) end
print("about to call delete_synth")
rc,msg = FS.delete_synth(synth)
if not rc then print(msg) end
print("about to call delete_settings")
rc,msg = FS.delete_settings(settings)
if not rc then print(msg) end

rc = FS.is_soundfont(Soundfont)
print("is_soundfont('"..Soundfont.."') returned", rc)
rc = FS.is_soundfont('/where/NO.sf2')
print("is_soundfont('/where/NO.sf2') returned", rc)
rc = FS.is_soundfont('/etc/passwd')
print("is_soundfont('/etc/passwd') returned", rc)
rc = FS.is_midifile(Midifile)
print("is_midifile('"..Midifile.."') returned", rc)
rc = FS.is_midifile('/where/NO.mid')
print("is_midifile('/where/NO.mid') returned", rc)
rc = FS.is_midifile('/etc/passwd')
print("is_midifile('/etc/passwd') returned", rc)

-- os.execute('play /tmp/t.wav') -- used to test file output

--[=[

=pod

=head1 NAME

test_fs - test script for fluidsynth.lua

=head1 SYNOPSIS

 lua test_fs

=head1 DESCRIPTION

This script

=head1 ARGUMENTS

=over 3

=item I<-v>

Print the Version

=back

=head1 DOWNLOAD

This at is available at

=head1 AUTHOR

Peter J Billam, http://www.pjb.com.au/comp/contact.html

=head1 SEE ALSO

 http://www.pjb.com.au/

=cut

]=]
