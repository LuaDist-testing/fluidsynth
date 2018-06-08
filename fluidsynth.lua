---------------------------------------------------------------------
--     This Lua5 module is Copyright (c) 2011, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This module is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------

local M = {} -- public interface
M.Version     = '1.0' -- switch pod and doc over to using moonrocks
M.VersionDate = '15aug2014'

local ALSA = nil -- not needed if you never use play_event
pcall(function() ALSA = require 'midialsa' end)

--  http://fluidsynth.sourceforge.net/api/ --

-------------------- private utility functions -------------------
local function warn(str) io.stderr:write(str,'\n') end
local function qw(s)  -- t = qw[[ foo  bar  baz ]]
    local t = {} ; for x in s:gmatch("%S+") do t[#t+1] = x end ; return t
end
local function deepcopy(object)  -- http://lua-users.org/wiki/CopyTable
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end
local function round(x) return math.floor(x+0.5) end
local function sorted_keys(t)
	local a = {}
	for k,v in pairs(t) do a[#a+1] = k end
	table.sort(a)
	return  a
end
local function touch(fn)
    local f=io.open(fn,'r') -- or check if posix.stat(path) returns non-nil
    if f then
		f:close(); return true
	else
    	f=io.open(fn,'w')
    	if f then
			f:write(""); f:close(); return true
		else
			return false
		end
	end
end
local function homedir(user)
	if not user and os.getenv('HOME') then return os.getenv('HOME') end
	local P = nil
    pcall(function() P = require 'posix' ; end )
    if type(P) == 'table' then  -- we have posix
		if not user then user = P.getpid('euid') end
		return P.getpasswd(user, 'dir') or '/tmp'
	end
	warn('fluidsynth: HOME not set and luaposix not installed; using /tmp')
	return '/tmp/'
end
local function tilde_expand(filename)
    if string.match(filename, '^~') then
        local user = string.match(filename, '^~(%a+)/')
        local home = homedir(user)
        filename = string.gsub(filename, '^~%a*', home)
    end
    return filename
end

---------------- from Lua Programming Gems p. 331 ----------------
local require, table = require, table -- save the used globals
local aux, prv = {}, {} -- auxiliary & private C function tables

local initialise = require 'C-fluidsynth'
initialise(aux, prv, M) -- initialise the C lib with aux,prv & module tables

------------------ fluidsynth-related variables -----------------
-- NAH; should get this from new_fluid_settings() !!
local DefaultOption = {   -- the default synthesiser options
	['synth.audio-channels']   = 1,      -- one stereo channel
	['synth.audio-groups']     = 1,      -- only LADSPA subsystems change this
	['synth.chorus.active']    = true,
	['synth.cpu-cores']        = 1,      -- experimental
	['synth.device-id']        = 0,      -- for SYSEXes
	['synth.dump']             = false,  -- unused
	['synth.effects-channels'] = 2,
	['synth.gain']             = 0.2,    -- number, not just integer
    ['synth.ladspa.active']    = false,
    ['synth.midi.channels']    = 16,
	['synth.midi-bank-select'] = 'gs',
    -- gm: ignores CC0 and CC32 messages.
    -- gs: (default) CC0 becomes the bank number, CC32 is ignored.
    -- xg: CC32 becomes the bank number, CC0 is ignored.
    -- mma: bank is calculated as CC0*128+CC32.
	['synth.min-note-length']  = 10,     -- milliseconds
	['synth.parallel-render']  = true,
	['synth.polyphony']        = 256,    -- how many voices can be played in parallel
	['synth.reverb.active']    = true,
	['synth.sample-rate']      = 44100,  -- number, not just integer
	['synth.threadsafe-api']   = true,   -- protected by a mutex
	['synth.verbose']          = false,  -- dumps MIDI events to stdout
	['audio.driver']           = 'jack',
	-- jack alsa oss pulseaudio coreaudio dsound portaudio sndman dart file 
	-- jack(Linux) dsound(Winds) sndman(MacOS9) coreaudio(MacOSX) dart(OS/2) 
	['audio.periods']          = 16,  -- 2..64
	['audio.period-size']      = 64,  -- 64..8192 audio-buffer size
	['audio.realtime-prio']    = 60,  -- 0..99
	['audio.sample-format']    = '16bits',  -- '16bits' or 'float'
	['audio.alsa.device']      = 'default',
	['audio.coreaudio.device'] = 'default',
	['audio.dart.device']      = 'default',
	['audio.dsound.device']    = 'default',
	['audio.file.endian']      = 'auto',
	['audio.file.format']      = 's16', -- double, float, s16, s24, s32, s8, u8
	-- ('s16' is all that is supported if libsndfile support not built in) 
	['audio.file.name']        = 'fluidsynth.wav',  -- .raw if no libsndfile
	['audio.file.type']        = 'auto',   -- aiff,au,auto,avr,caf,flac,htk
	-- iff, mat, oga, paf, pvf, raw, sd2, sds, sf, voc, w64, wav, xi
	-- (actual list of types may vary and depends on the libsndfile
	-- library used, 'raw' is the only type available if no libsndfile
	-- support is built in).
	['audio.jack.autoconnect'] = false,
	['audio.jack.id']          = 'fluidsynth',
	['audio.jack.multi']       = false,
	['audio.jack.server']      = '',   -- empty string = default jack server
	['audio.oss.device']       = '/dev/dsp',
	['audio.portaudio.device'] = 'PortAudio Default',
	['audio.pulseaudio.device'] = 'default',
	['audio.pulseaudio.server'] = 'default',
}

------------------------ public functions ----------------------

local FLUID_FAILED = -1  -- /usr/include/fluidsynth/misc.h

function M.new_settings()
	local rc = prv.new_fluid_settings()
	if rc == FLUID_FAILED then return nil, 'new_fluid_settings failed'
	else return rc end
end

function M.synth_error(synth)
 	-- Get a textual representation of the most recent synth error. 
	return prv.fluid_synth_error(synth)
end

function M.set(settings, key, val)   -- there are also the _get routines...
	if type(key) == 'nil' then
		return nil, "fluidsynth: can't set the value for a nil key"
	end
	if type(key) ~= 'string' then
		return nil,"fluidsynth: the setting key "..tostring(key).." has to be a string"
	end
	if type(val) == 'nil' then
		return nil, "fluidsynth: can't set the "..key.." key to nil"
	end
	if type(val) == type(DefaultOption[key]) then
		if key=='synth.sample-rate' or key=='synth.gain' then
			-- should I use fluid_synth_set_gain(), fluid_synth_set_polyphony()
			local rc = prv.fluid_settings_setnum(settings, key, val) -- ??
			if rc == 1 then return true
			else return nil,M.synth_error(synth) end
		elseif type(val) == 'number' then
			-- or fluid_synth_setint !! but this seem to not exist :-(
			local rc = prv.fluid_settings_setint(settings, key, round(val))
			if rc == 1 then return true
			else return nil,M.synth_error(synth) end
		elseif type(val) == 'string' then
			local rc = prv.fluid_settings_setstr(settings, key, val)
			if rc == 1 then return true
			else return nil,M.synth_error(synth) end
		else
			return nil,'fluidsynth knows no '..key..' setting of '..type(val)..' type'
		end
	else
		return nil, 'fluidsynth knows no '..key..' setting'
	end
	return true
end

function M.new_synth(settings)
	-- "The settings parameter is used directly,
	--  and should not be modified or freed independently."
	local synth = prv.new_fluid_synth(settings)
	if synth == FLUID_FAILED then return nil, 'new_synth() failed'
	else return synth end
end

function M.new_audio_driver(settings, synth)
	local audio_driver = prv.new_fluid_audio_driver(settings, synth)
	if audio_driver == FLUID_FAILED then return nil, M.synth_error(synth)
	else return audio_driver end
end

function M.new_player(synth)
	local player = prv.new_fluid_player(synth)
	if player == FLUID_FAILED then return nil, M.synth_error(synth)
	else return player end
end

function M.player_add(player, midifilename)
	local rc = prv.fluid_player_add(player, midifilename)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.player_play(player)
	local rc = prv.fluid_player_play(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.player_join(player)
	local rc = prv.fluid_player_join(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.player_stop(player)
	local rc = prv.fluid_player_stop(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.sf_load(synth, filename)
	-- Returns: SoundFont ID on success, FLUID_FAILED=-1 on error 
	-- should probaby redirect stderr to /tmp/x
	-- and then filter out "can't use ROM samples" lines...
	local sf_id = prv.fluid_synth_sfload(synth, filename)
	if sf_id == FLUID_FAILED then return nil, M.synth_error(synth)
	else return sf_id end
end

function M.sf_select(synth, channel, sf_id)
	local rc = prv.fluid_synth_sfont_select(synth, channel, sf_id)
	if rc == FLUID_FAILED then
		return nil, 'sf_select: '..M.synth_error(synth)
	else return true end
end

function M.patch_change(synth, channel, patch)
	local rc = prv.fluid_synth_program_change(synth, channel, patch)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.control_change(synth, channel, cc, val)
	local rc = prv.fluid_synth_cc(synth, channel, cc, val)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.note_on(synth, channel, note, velocity)
	local rc = prv.fluid_synth_noteon(synth, channel, note, velocity)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.note_off(synth, channel, note)
	local rc = prv.fluid_synth_noteoff(synth, channel, note)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.pitch_bend(synth, channel, val) -- val = 0..8192..16383
	local rc = prv.fluid_synth_pitch_bend(synth, channel, val)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.pitch_bend_sens(synth, channel, val) -- val = semitones
	local rc = prv.fluid_synth_pitch_bend_sens(synth, channel, val)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.delete_audio_driver(audio_driver)
	local rc = prv.delete_fluid_audio_driver(audio_driver)
	if rc == FLUID_FAILED then return nil, 'delete_audio_driver failed'
	else return true end
end

function M.delete_player(player)
	local rc = prv.delete_fluid_player(player)
	if rc == FLUID_FAILED then return nil, 'delete_player failed'
	else return true end
end

function M.delete_synth(synth)
	local rc = prv.delete_fluid_synth(synth)
	if rc == FLUID_FAILED then
		return nil, 'delete_synth: '..M.synth_error(synth)
	else return true end
end

function M.delete_settings(settings)
	local rc = prv.delete_fluid_settings(settings)
	if rc == FLUID_FAILED then return nil, 'delete_settings failed'
	else return true end
end

function M.is_soundfont(filename)
	return prv.fluid_is_soundfont(filename)
end

function M.is_midifile(filename)
	return prv.fluid_is_midifile(filename)
end

--------- wrapper routines for integration with midiasla.lua and MIDI.lua

local function is_noteoff(alsaevent)
    if alsaevent[1] == ALSA.SND_SEQ_EVENT_NOTEOFF then return true end
    if alsaevent[1] == ALSA.SND_SEQ_EVENT_NOTEON and alsaevent[8][3] == 0 then
       return true
    end
    return false
end
function M.play_event(synth, event) -- no queuing yet; immediate output only
	if #event == 8 then  -- its a midialsa event
		-- see:  http://www.pjb.com.au/comp/lua/midialsa.html#input
		-- and:  http://www.pjb.com.au/comp/lua/midialsa.html#constants
		if ALSA == nil then
			warn('you need to install midialsa.lua !')
			warn('see http://www.pjb.com.au/comp/lua/midialsa.html#download')
			return nil
		end
		local event_type = event[1]
		local data       = event[8]
		if is_noteoff(event) then
			M.note_off(synth, data[1], data[2])
		elseif event_type == ALSA.SND_SEQ_EVENT_NOTEON then
			M.note_on(synth, data[1], data[2], data[3])
		elseif event_type == ALSA.SND_SEQ_EVENT_CONTROLLER then
			M.control_change(synth, data[1], data[5], data[6])
		elseif event_type == ALSA.SND_SEQ_EVENT_PGMCHANGE then
			M.patch_change(synth, data[1], data[6])
		elseif event_type == ALSA.SND_SEQ_EVENT_PITCHBEND then
			-- pitchwheel; snd_seq_ev_ctrl_t; data is from -8192 to 8191 !
			M.pitch_bend(synth, data[1], data[6]+8192)
		end
	elseif type(event[1]) == 'string' then  -- it's a MIDI.lua event
		-- see:  http://www.pjb.com.au/comp/lua/MIDI.html#events
		local event_type = event[1]
		if event_type == 'note_off'
		  or (event_type == 'note_on' and event[5]==0) then
			M.note_off(synth, event[3], event[4])
		elseif event_type == 'note_on' then
			M.note_on(synth, event[3], event[4], event[5])
		elseif event_type == 'control_change' then
			M.control_change(synth, event[3], event[4], event[5])
		elseif event_type == 'patch_change' then
			M.patch_change(synth, event[3], event[4])
		elseif event_type == 'pitch_wheel_change' then
			M.pitch_bend(synth, event[3], event[4], event[5])
		end
	end
	-- return ?
end

return M

--[[

=pod

=head1 NAME

C<fluidsynth> - a Lua interface to the I<fluidsynth> library

=head1 SYNOPSIS

 local FS = require 'fluidsynth'
 local settings = FS.new_settings()
 FS.set("audio.driver", "jack")
 local synth    = FS.new_synth(settings)
 local adriver  = FS.new_audio_driver(settings, synth)
 assert(FS.sf_load("/home/soundfonts/MyGM.sf2", 1))
 local channel = 5
 FS.patch_change(synth, channel, 87)
 FS.control_change(synth, channel, 7, 127)
 FS.noteon(synth, channel, 60, 100)   -- note, velocity
 os.execute('sleep 2')
 FS.noteoff(synth, channel, 60)       -- note
 FS.delete_audio_driver(adriver)
 FS.delete_synth(synth)
 FS.delete_settings(settings)

=head1 DESCRIPTION

This Lua module offers a simplified calling interface
to the Fluidsynth Library.

It is early in its very early versions,
and the API is expected to change and evolve.

It is a relatively thick wrapper; the library's voluminous
output on stderr has been redirected so the module can be used
for example within a I<Curses> app, and the return codes on failure
have adopted the I<nil,errormessage> convention of Lua
so they can be used for example with I<assert()>

=head1 FUNCTIONS

Unless otherwise stated,
these functions all return I<nil,errormessage> on failure.

=head3 settings = FS.new_settings()

This corresponds to the library routine I<new_fluid_settings()>
The return value is a C pointer, so if you mess with it the library will crash.

=head3 FS.set(settings, "audio.driver", "alsa")

This corresponds to the library routines
I<fluid_settings_setstr()>,
I<fluid_settings_setnum()>, and
I<fluid_settings_setint()>.
The module knows which type each parameter should be,
and calls the correct routine automatically.

=head3 synth = FS.new_synth(settings)

This corresponds to the library routine I<new_fluid_synth()>
The return value is a C pointer, so if you mess with it the library will crash.

=head3 sf_id = FS.sf_load(synth, 'filename.sf2')

This corresponds to the library routine I<(fluid_synth_sfload)>

It returns the soundfont_id,
which is a C pointer, so don't mess with it.

A I<synth> may load more than one soundfont;
they go onto a sort of stack, and for a given patch,
I<fluidsynth> will use that soundfont closest to the top of the
stack which can supply the requested patch. For example:

 assert(FS.sf_load(synth, 'MyGM.sf2')) -- the piano is not good
 assert(FS.sf_load(synth, 'MyReallyGoodPiano.sf2'))

=head3 audio_driver = FS.new_audio_driver(settings, synth)

This corresponds to the library routine I<new_fluid_audio_driver()>
The return value is a C pointer.

=head3 midiplayer = FS.new_player(synth)

This corresponds to the library routine I<new_fluid_player()>
The return value is a C pointer.

=head3 FS.player_add(midiplayer, midifilename)

This corresponds to the library routine I<fluid_player_add()>

=head3 FS.player_play(midiplayer)

This corresponds to the library routine I<fluid_player_play()>

=head3 FS.note_on(synth, channel, note, velocity)

This corresponds to the library routine I<fluid_synth_noteon()>

=head3 FS.note_off(synth, channel, note, velocity)

This corresponds to the library routine I<fluid_synth_noteoff()>

=head3 FS.patch_change(synth, channel, patch)

This corresponds to the library routine I<fluid_synth_program_change()>

=head3 FS.control_change(synth, channel, controller, value)

This corresponds to the library routine I<fluid_synth_cc()>

=head3 FS.pitch_bend(synth, channel, val)

This corresponds to the library routine I<fluid_synth_pitch_bend()>.
The value should lie between 0 and 16383,
where 8192 represents the default, central, pitch-wheel position.

=head3 FS.play_event(synth, event)

This is a wrapper for the above I<note_on>, I<note_off>, I<patch_change>,
I<control_change> and I<pitch_bend routines>, which accepts events
of two different types used in the author's other midi-related modules:

1) midialsa events, see: http://www.pjb.com.au/comp/lua/midialsa.html

2) MIDI 'opus' events, see: http://www.pjb.com.au/comp/lua/MIDI.html#events

It will currently only handle real-time events,
so every event received will be played immediately.
It will currently not handle 'note' events (of either type).

=head3 local ok = FS.is_soundfont(filename)

This corresponds to the library routine I<fluid_is_soundfont()>
which checks for the "RIFF" header in the file.
It is useful only to distinguish between SoundFont and MIDI files.  

=head3 local ok = FS.is_midifile(filename)

This corresponds to the library routine I<fluid_is_midifile()>
The current implementation only checks for the "MThd" header in the file.
It is useful only to distinguish between SoundFont and MIDI files. 

=head3 FS.delete_settings(settings)

This corresponds to the library routine I<delete_fluid_settings()>

=head3 FS.delete_synth(synth)

This corresponds to the library routine I<delete_fluid_synth()>

=head3 FS.delete_audio_driver(audio_driver)

This corresponds to the library routine I<delete_fluid_audio_driver()>

=head3 FS.delete_player(midiplayer)

This corresponds to the library routine I<delete_fluid_player()>

=head1 EXAMPLE

 #!/usr/bin/lua
 -- a functional alsa-client soundfont-synth !
 local FS   = require 'fluidsynth'
 local ALSA = require 'midialsa'
 local Input     = 14
 local Soundfont = '/home/soundfonts/MyGM.sf2'
 ALSA.client( 'fluidsynth alsa client', 1, 0, false )
 ALSA.connectfrom( 0, Input )
 local settings = FS.new_settings()
 FS.set(settings, "audio.driver", "alsa")
 FS.set(settings, "audio.periods", 2)       -- min, for low latency
 FS.set(settings, "audio.period-size", 64)  -- min, for low latency
 local synth = FS.new_synth(settings)
 local audio_driver = FS.new_audio_driver(settings, synth)
 local sf_id = FS.sf_load(synth, Soundfont, 0)
 -- you will need to set a patch before any output can be generated!
 while true do
   local alsaevent = ALSA.input()
   if alsaevent[1]==ALSA.SND_SEQ_EVENT_PORT_UNSUBSCRIBED then break end
   FS.play_event(synth, alsaevent)
 end
 FS.delete_audio_driver(audio_driver)
 FS.delete_synth(synth)
 FS.delete_settings(settings)

=head1 DOWNLOAD

This module is available as a LuaRock in
http://rocks.moonscript.org/modules/peterbillam
so you should be able to install it with the command:

 $ su
 Password:
 # luarocks install --server=http://rocks.moonscript.org fluidsynth

or:

 # luarocks install http://www.pjb.com.au/comp/lua/fluidsynth-1.0-0.rockspec

It depends on the I<fluidsynth> library and its header-files;
for example on Debian you may need:

 # aptitude install libfluidsynth libfluidsynth-dev

or on Centos you may need:

 # yum install fluidsynth-devel

=head1 CHANGES

 20140818 1.0 first working version 

=head1 AUTHOR

Peter Billam, 
http://www.pjb.com.au/comp/contact.html

=head1 SEE ALSO

=over 3

 man fluidsynth
 /usr/include/fluidsynth.h
 /usr/include/fluidsynth/*.h
 http://fluidsynth.sourceforge.net/api/
 http://www.pjb.com.au
 http://www.pjb.com.au/comp/index.html#lua
 http://www.pjb.com.au/comp/lua/fluidsynth.html
 http://www.pjb.com.au/comp/lua/midialsa.html
 http://www.pjb.com.au/comp/lua/MIDI.html

=back

=cut
]]
