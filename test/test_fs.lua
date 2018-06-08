#!/usr/bin/lua
---------------------------------------------------------------------
--     This Lua5 script is Copyright (c) 2014, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This script is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------
local Version = '2.0  for Lua5'
local VersionDate  = '25apr2015';
local Synopsis = [[
program_name [options] [filenames]
]]
local Midifile = 'folkdance.mid'
require 'DataDumper'

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
local userconf = FS.get_userconf()
print ('get_userconf returns', userconf)
local sysconf = FS.get_sysconf()
print ('get_sysconf returns', sysconf)
local parameter2default = FS.default_settings()
print("parameter2default['synth.midi-bank-select'] =",parameter2default['synth.midi-bank-select'])
print("about to call read_config_file")
local soundfonts,msg = FS.read_config_file()
print(DataDumper(soundfonts))
print("about to call new_synth")
local synth,msg = FS.new_synth()
if synth == nil then print(msg) end
-- if audio.driver==alsa, could read /proc/asound/devices to help
-- guess best choice for audio.alsa.device (such as: "hw:0", "plughw:1")

local val,msg = FS.get(synth,'synth.audio-groups')
print('synth.audio-groups is',val)
local val,msg = FS.get(synth,'synth.midi-bank-select')
print('synth.midi-bank-select is',val)
local val,msg = FS.get(synth,'synth.gain')
print('synth.gain is',val)
local val,msg = FS.get(synth,'sprogthwloop')
print('sprogthwloop is',val, msg)

print("about to call sf_load")
local sf_ids,msg = FS.sf_load(synth, soundfonts)
if sf_ids == nil then print(msg) end
print('sf_ids =',DataDumper(sf_ids))
print("about to call sf_load on non-existent file")
sf_ids,msg = FS.sf_load(synth, "/wherever/Zsfuospw9erk.sf2", 0)
print('sf_ids =',DataDumper(sf_ids))

print("about to call new_player on non-existent MIDI data")
rc,msg = FS.new_player(synth,
  'qwert yuiop asdfg hjkl; zxcvb nm, qwert yuiop asdfg hjkl; zxcvb nm,')
if not rc then print(msg) end

local filename = '/home/pjb/www/muscript/samples/courante.mid'
fh = assert(io.open(filename, "rb"))
local midi = fh:read('*all')
fh:close()
print('courante.mid length is '..string.len(midi)..' bytes')
if string.match(midi, '^MThd') then
	print('and it begins with MThd')
end
print('about to call new_player on in-memory MIDI data')
local player = assert(FS.new_player(synth, midi))
FS.player_play(player)
FS.player_join(player)


local channel = 0
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

if not rc then print(msg) end
print("about to call delete_synth(nil)")
rc,msg = FS.delete_synth(nil)
if not rc then print(msg) end

rc = FS.is_soundfont(soundfonts[1])
print("is_soundfont('"..soundfonts[1].."') returned", rc)
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
