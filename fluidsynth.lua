---------------------------------------------------------------------
--     This Lua5 module is Copyright (c) 2011, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This module is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------

local M = {} -- public interface
M.Version     = '1.6' --  delete_synth doesn't automatically remove TmpFile
M.VersionDate = '01sep2014'

local ALSA = nil -- not needed if you never use play_event

local Synth2settings       = {}
local AudioDriver2synth    = {}
local Player2synth         = {}
local Synth2fastRender     = {}
local ConfigFileSettings   = {}
local FLUID_FAILED         = -1  -- /usr/include/fluidsynth/misc.h
local TmpName              = nil -- used to save the C-library's stderr

-- http://fluidsynth.sourceforge.net/api/
-- http://fluidsynth.sourceforge.net/api/index.html#Sequencer
-- sequencer = new_fluid_sequencer2(0);
-- synthSeqID = fluid_sequencer_register_fluidsynth(sequencer, synth);
-- mySeqID = fluid_sequencer_register_client(sequencer,"me",seq_callback,NULL);
-- seqduration = 1000;  /* ms */
-- delete_fluid_sequencer(sequencer);

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

function is_readable(filename)
	local f,msg = io.open(filename, 'r')
	if not f then return false, msg end
	io.close(f) 
	return true
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
	['audio.jack.autoconnect']  = false,
	['audio.jack.id']           = 'fluidsynth',
	['audio.jack.multi']        = false,
	['audio.jack.server']       = '',   -- empty string = default jack server
	['audio.oss.device']        = '/dev/dsp',
	['audio.portaudio.device']  = 'PortAudio Default',
	['audio.pulseaudio.device'] = 'default',
	['audio.pulseaudio.server'] = 'default',
	['player.reset-synth']      = true,
	['player.timing-source']    = 'sample',
	['fast.render']             = false, -- NON-STANDARD, not in library API
}

------------------------ private functions ----------------------

function new_settings()
	TmpName = prv.redirect_stderr()
	local settings = prv.new_fluid_settings()
	if settings==FLUID_FAILED then return nil,'new_fluid_settings failed' end
	return settings
end

function new_audio_driver(settings, synth)
	local audio_driver = prv.new_fluid_audio_driver(settings, synth)
	if audio_driver == FLUID_FAILED then return nil, M.synth_error(synth) end
	AudioDriver2synth[audio_driver] = synth
	return audio_driver
end

function delete_audio_driver(audio_driver)
	local rc = prv.delete_fluid_audio_driver(audio_driver)
	if rc == FLUID_FAILED then return nil, 'delete_audio_driver failed' end
	AudioDriver2synth[audio_driver] = nil
	return true
end

function delete_player(player)
	local rc = prv.delete_fluid_player(player)
	if rc == FLUID_FAILED then return nil, 'delete_player failed' end
	Player2synth[player] = nil
	return true
end

local function is_noteoff(alsaevent)
    if alsaevent[1] == ALSA.SND_SEQ_EVENT_NOTEOFF then return true end
    if alsaevent[1] == ALSA.SND_SEQ_EVENT_NOTEON and alsaevent[8][3] == 0 then
       return true
    end
    return false
end

------------------------ public functions ----------------------


function M.synth_error(synth)   -- undocumented
 	-- Get a textual representation of the most recent synth error
	return prv.fluid_synth_error(synth)
end

function M.error_file_name()   -- so the app can remove it
	return TmpName
end

function set(settings, key, val)   -- there are also the _get routines...
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
			local rc = prv.fluid_settings_setnum(settings, key, val)
			if rc == 1 then return true
			else return nil,M.synth_error(synth) end
		elseif type(val) == 'number' then
			local rc = prv.fluid_settings_setint(settings, key, round(val))
			if rc == 1 then return true
			else return nil,M.synth_error(synth) end
		elseif type(val) == 'boolean' then   -- 1.1
			local v = 0
			if val then v = 1 end
			local rc = prv.fluid_settings_setint(settings, key, v)
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

----------------------- basic functions ---------------------

function M.read_config_file(filename)
	if not filename then
		userconf = prv.fluid_get_userconf()
		sysconf  = prv.fluid_get_sysconf()
		if    is_readable(userconf) then filename = userconf
		elseif is_readable(sysconf) then filename = sysconf
		else return nil, "can't find either "..userconf.." or "..sysconf
		end
	end
	local soundfonts = {}
	local config_file,msg = io.open(filename, 'r')
	if not config_file then return nil,msg end   -- no config file
	ConfigFileSettings = {}
	while true do
		local line = config_file:read('*l')
		if not line then break end
		local param,val = string.match(line, '^%s*set%s*(%S+)%s*(%S+)%s*$')
		if param and val then
			local default_val = DefaultOption[param]
			if default_val then
				if type(default_val) == 'number' then val = tonumber(val)
				elseif type(default_val) == 'boolean' then
					if val == 'true' or val == '1' then val = true
					else val = false
					end
				end
				ConfigFileSettings[param] = val
			end
		else
			local sf_file = string.match(line, '^%s*load%s*(%S+)%s*$')
			if sf_file and M.is_soundfont(sf_file) then
				table.insert(soundfonts, sf_file)
			end
		end
	end
	config_file:close()
	return soundfonts
end

function M.new_synth(arg)
	-- "The settings parameter is used directly,
	--  and should not be modified or freed independently."
	if arg == nil then arg = { } end
	local arg_type = type(arg)
	if arg_type == 'table' then
		-- invoking new_synth with a table of settings invokes
		--  new_settings, set, new_synth, new_audio_driver automatically.
		local settings = new_settings()
		for k,v in pairs(arg) do
			if k ~= 'fast.render' then set(settings, k, v) end
		end
		for k,v in pairs(ConfigFileSettings) do
			if k ~= 'fast.render' then set(settings, k, v) end
		end
		local synth = prv.new_fluid_synth(settings)
		if synth == FLUID_FAILED then return nil, 'new_synth() failed' end
		if arg['fast.render'] then   -- from src/fluidsynth.c
			Synth2fastRender[synth] = true
			set(settings, 'player.timing-source', 'sample')
			set(settings, 'synth.parallel-render', 1)
			-- fast_render should not need this, but currently does
		end
		Synth2settings[synth] = settings
		if not Synth2fastRender[synth] and arg['audio.driver'] ~= 'none' then
			local audio_driver = new_audio_driver(settings, synth)
		end
		return synth   -- that's an integer cast of a C-pointer
--	elseif arg_type == 'number' then
--		print ('DEPRECATED: new_synth(number) ; arg must be a table !!')
--		local settings = arg
--		local synth = prv.new_fluid_synth(settings)
--		if synth == FLUID_FAILED then return nil, 'new_synth() failed' end
--		Synth2settings[synth] = settings
--		return synth
	else
		local msg = 'fluidsynth: new_synth arg must be table, not '
		return nil, msg..arg_type
	end
end

function M.sf_load(synth, filenames )
	if type(filenames) == 'string' then
		local sf_id = prv.fluid_synth_sfload(synth, filename)
		if sf_id == FLUID_FAILED then return nil, M.synth_error(synth)
		else return { sf_id } end
	elseif type(filenames) == 'table' then
		local filename2sf_id = {}
		for k,filename in ipairs(filenames) do
			local sf_id = prv.fluid_synth_sfload(synth, filename)
			if sf_id == FLUID_FAILED then return nil, M.synth_error(synth)
			else filename2sf_id[filename] = sf_id
			end
		end
		return filename2sf_id
	else
		return nil, "fluidsynth: sf_load 2nd arg must be string or array"
	end
end

function M.sf_select(synth, channel, sf_id)   -- not documented :-(
	local rc = prv.fluid_synth_sfont_select(synth, channel, sf_id)
	if rc == FLUID_FAILED then
		return nil, 'sf_select: '..M.synth_error(synth)
	else return true end
end

function M.delete_synth(synth)
	if synth == nil then   -- if synth==nil it deletes all synths
		for k,v in pairs(Synth2settings) do
			local rc, msg = M.delete_synth(k)
			if not rc then return rc, msg end
		end
		-- 1.6: os.remove(TmpName) No. See below...
		return true
	end
	-- search though Player2synth deleting any dependent players
	for k,v in pairs(Player2synth) do
		if v == synth then delete_player(k) end
	end
	-- search though AudioDriver2synth deleting any dependent audio_drivers
	for k,v in pairs(AudioDriver2synth) do
		if v == synth then delete_audio_driver(k) end
	end
	local rc = prv.delete_fluid_synth(synth)
	if rc == FLUID_FAILED then
		return nil, 'delete_synth: '..M.synth_error(synth)
	end
	local settings = Synth2settings[synth]
	if settings then prv.delete_fluid_settings(settings) end
	Synth2settings[synth]   = nil
	Synth2fastRender[synth] = nil
	-- 1.6  if #Synth2settings < 0.5 then os.remove(TmpName) end
	-- No. eg: in fluadity -d, synths get stopped and started.
	return true
end

--------------- functions for playing midi files ----------------

function M.new_player(synth, midifile)
	if not midifile then return nil,'new_player: midifile was nil' end
	local player = prv.new_fluid_player(synth)
	if player == FLUID_FAILED then return nil, M.synth_error(synth) end
	local rc
	if M.is_midifile(midifile) then   -- 1.5
		rc = prv.fluid_player_add(player, midifile)
	elseif midifile == '-' then
		rc = M.player_add_mem(player, io.stdin:read('*a'))
	elseif string.match(midifile, '^MThd') then
		rc = M.player_add_mem(player, midifile)
	else
		delete_player(player)
		midifile = string.gsub(string.sub(midifile,1,40), '%G+', '.')
		return nil, 'new_player: '..midifile..' was not a midi file'
	end
	if rc == FLUID_FAILED then
		delete_player(player)
		return nil, M.synth_error(synth)
	end
	Player2synth[player] = synth
	return player
end

-- Superfluous... it seems impossible to add a second midifile to a player,
-- even after the first midifile has finished playing. Just use M.new_player
--function M.player_add(player, midifilename)
--	if not midifilename then return nil,'player_add: midifilename was nil' end
--	if not M.is_midifile(midifilename) then
--		return nil,'player_add: '..midifilename..' was not a midi file'
--	end
--	local rc = prv.fluid_player_add(player, midifilename)
--	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
--	else return true end
--end

function M.player_play(player)
	local rc = prv.fluid_player_play(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(Player2synth[player])
	else return true end
end

function M.player_join(player)
	-- When should FastRender be invoked ?  Well, it needs knowledge
	-- of the future; it's not quite enough for a player to be running
	-- and for the output to be a wav file, because real-time events
	-- might get fed to the synth while the midi file is playing :-(
	local synth    = Player2synth[player]
	local settings = Synth2settings[synth]
	if synth and settings and Synth2fastRender[synth] then  -- just midi->wav
		local rc = prv.fast_render_loop(settings, synth, player)
		return true
	end
	local rc = prv.fluid_player_join(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(synth)
	else return true end
end

function M.player_stop(player)
	local rc = prv.fluid_player_stop(player)
	if rc == FLUID_FAILED then return nil, M.synth_error(Player2synth[player])
	else
		-- player_play can not be reinvoked ! so just delete_player
		delete_player(player)
		return true
	end
end

function M.player_add_mem(player, buffer)
	local rc = prv.fluid_player_add_mem(player, buffer, string.len(buffer)+1)
	if rc == FLUID_FAILED then return nil, M.synth_error(Player2synth[player])
	else return true
	end
end

----------------- functions for playing in real-time -------------

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

function M.play_event(synth, event) -- no queuing yet; immediate output only
	if #event == 8 then  -- its a midialsa event
		-- see:  http://www.pjb.com.au/comp/lua/midialsa.html#input
		-- and:  http://www.pjb.com.au/comp/lua/midialsa.html#constants
		pcall(function() ALSA = require 'midialsa' end)
		if ALSA == nil then
			return nil, 'you need to install midialsa.lua !'
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

------------------- functions returning state -----------------

function M.is_soundfont(filename)
	return prv.fluid_is_soundfont(filename)
end

function M.is_midifile(filename)
	return prv.fluid_is_midifile(filename)
end

function M.default_settings()
	return deepcopy(DefaultOption)
end

function M.all_synth_errors(synth)
 	-- slurp the temp file which stored the redirected stderr
	if not TmpName then return '' end
	local tmpfile = io.open(TmpName, 'r')
	if not tmpfile then return '' end
	local str = tmpfile:read('*a')
	tmpfile:close()
	return str
end

function M.get_sysconf()   -- undocumented
	return prv.fluid_get_sysconf()
end

function M.get_userconf()   -- undocumented
	return prv.fluid_get_userconf()
end

---------------------------------------------------------------

return M

--[[

=pod

=head1 NAME

C<fluidsynth> - a Lua interface to the I<fluidsynth> library

=head1 SYNOPSIS

 local FS = require 'fluidsynth'   -- convert midi to wav
 local soundfonts = FS.read_config_file()  -- default ~/.fluidsynth
 local synth1   = FS.new_synth(
   ['synth.gain']      = 0.4,      -- be careful...
   ['audio.driver']    = 'file',
   ['audio.file.name'] = 'foo.wav',
   ['fast.render']     = true,     -- not part of the C-library API
 } )
 local sf2id = FS.sf_load(synth1, soundfonts)
 local player1  = FS.new_player(synth1, 'foo.mid')
 assert(FS.player_play(player1))
 assert(FS.player_join(player1))   -- wait for foo.mid to finish
 os.execute('sleep 1')             -- don't chop final reverb
 FS.delete_synth(synth1) -- deletes player,audio_driver,synth,settings

 local FS   = require 'fluidsynth' -- an alsa-client soundfont-synth
 local ALSA = require 'midialsa'
 local soundfonts = FS.read_config_file('/unusual/config_file')
 ALSA.client( 'fluidsynth-alsa-client', 1, 0, false )
 ALSA.connectfrom( 0, 'ProKeys' )
 local synth2 = FS.new_synth( {
   "audio.driver"      = "alsa",
   "audio.periods"     = 2,   -- min, for low latency
   "audio.period-size" = 64,  -- min, for low latency
 } )
 local sf2id = FS.sf_load(synth2, soundfonts)
 -- you will need to set a patch before any output can be generated!
 while true do
   local alsaevent = ALSA.input()
   if alsaevent[1]==ALSA.SND_SEQ_EVENT_PORT_UNSUBSCRIBED then break end
   FS.play_event(synth2, alsaevent)
 end
 FS.delete_synth(synth2)

=head1 DESCRIPTION

This Lua module offers a simplified calling interface
to the Fluidsynth Library.

It is in its early versions, and the API is expected to evolve.

It is a relatively thick wrapper.
Various higher-level FUNCTIONS are introduced,
the library's voluminous output on I<stderr> has been redirected
so the module can be used for example within a I<Curses> app,
and the return codes on failure have adopted the I<nil,errormessage>
convention of Lua so they can be used for example with I<assert()>.

=head1 FUNCTIONS

These functions wrap the I<fluidsynth> library functions
in a way that retains functionality,
but is easy to use and hides some of the dangerous internals.
Unless otherwise stated,
these functions all return I<nil,errormessage> on failure.

=head3 synth = FS.new_synth({['synth.gain']=0.3, ['audio.driver']='alsa',})

When called with no argument, or with a table argument,
I<new_synth> wraps the library routines I<new_fluid_synth()>,
invoking I<new_fluid_settings>, I<fluid_settings_setstr()>,
I<fluid_settings_setnum()>, and I<fluid_settings_setint()>,
and i<new_fluid_audio_driver()> automatically as needed.

The return value is a C pointer to the I<synth>,
so don't change that otherwise the library will crash.

Multiple synths may be started.

The meanings and permitted values of the various parameters are documented in
http://fluidsynth.sourceforge.net/api/
with just two additions:

B<1)> If the I<audio.driver> parameter is set to "none"
then FS.new_synth() will not automatically create an I<audio_driver>.
You will not need this until support for I<midi_router> is introduced.

B<2)> The I<fast.render> parameter is introduced.
You should set it to I<true> if and only if
you are converting MIDI to WAV and no real-time events are involved.
If I<fast.render> is I<true> the conversion will be done at full CPU speed
and will finish an order of magnitude quicker than real time.
Look for I<fast_render> in I<src/fluidsynth.c> for example code.

=head3 array_of_sf_ids = FS.sf_load(synth, {'my_gm.sf2', 'my_piano.sf2',})

This wraps the library routine I<fluid_synth_sfload()>,
calling it once for each soundfont.
Often, a I<synth> has more than one soundfont;
they go onto a sort of stack, and for a given patch,
I<fluidsynth> will use that soundfont closest to the top of the
stack which can supply the requested patch.
In the above example, I<my_gm.sf2> is a good general-midi soundfont,
except that I<my_piano.sf2> offers a much nicer piano sound.

It returns a table of fsoundfont_ids, which are stack indexes
starting from 1.
These soundfont_ids are only needed if you want to invoke
I<fluid_synth_sfunload()> or I<fluid_synth_sfreload()>,
so in most cases you can ignore the return value.

=head3 player = FS.new_player(synth, '/tmp/filename.mid')

This wraps the library routines I<new_fluid_player()>
and I<fluid_player_add()>,
thus allowing you to play a midi file.
The return value is a C pointer.

One I<synth> may have multiple I<midi_players> running at the same time
(eg: to play several midi files, each starting at a different moment).
Therefore, you still need to call I<player_play(player)>,
I<player_join(player)> and I<player_stop(player)> by hand.

=head3 FS.delete_synth(synth)

This does all the administrivia necessary to delete the I<synth>,
invoking I<delete_fluid_player>, I<delete_fluid_audio_driver>,
I<delete_fluid_synth> and I<delete_fluid_settings> as necessary.

When called with no argument it deletes all running I<synths>.

=head1 LOW-LEVEL FUNCTIONS YOU STILL NEED

Unless otherwise stated,
these functions all return I<nil,errormessage> on failure.

=head3 parameter2default = FS.default_settings()

Returns a table of all the supported parameters, with their default values.
This could be useful, for example, in an application,
to offer the user a menu of available parameters.

The meanings and permitted values of the various parameters, are documented in
http://fluidsynth.sourceforge.net/api/

=head3 FS.player_play(midiplayer)

This corresponds to the library routine I<fluid_player_play()>

=head3 FS.player_join(midiplayer)

This corresponds to the library routine I<fluid_player_join()>

=head3 FS.player_stop(midiplayer)

This corresponds to the library routine I<fluid_player_stop()>

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

1) MIDI 'opus' events, see: http://www.pjb.com.au/comp/lua/MIDI.html#events

2) midialsa events, see: http://www.pjb.com.au/comp/lua/midialsa.html

It will currently only handle real-time events,
so every event received will be played immediately.
It will currently not handle 'note' events (of either type).

=head3 local ok = FS.is_soundfont(filename)

This corresponds to the library routine I<fluid_is_soundfont()>
which checks for the "RIFF" header in the file.
It is useful only to distinguish between SoundFont and MIDI files.  
It returns only I<true> or I<false>.

=head3 local ok = FS.is_midifile(filename)

This corresponds to the library routine I<fluid_is_midifile()>
The current implementation only checks for the "MThd" header in the file.
It is useful only to distinguish between SoundFont and MIDI files. 
It returns only I<true> or I<false>.


=head1 CONFIGURATION FILE

The default configuration file is I<$HOME/.config/fluidsynth>
which can also be used as a configuration file for the
I<fluidsynth> executable, for example:

 fluidsynth -f ~/.config/fluidsynth

But this module only recognises two types of command,
the first of which is ignored by I<fluidsynth>.
This is the format:

 audio.driver = alsa
 synth.polyphony = 1024
 load /home/soundfonts/MyGM.sf2
 load /home/soundfonts/ReallyGoodPiano.sf2

Invoking the function I<soundfonts = FS.read_config_file()>
(before creating the first I<synth>!)
changes the default settings for I<audio.driver> and I<synth.polyphony>,
and returns an array of Soundfonts
ready for later use by I<sf_load(synth,soundfonts)>

=head1 DOWNLOAD

This module is available as a LuaRock in
http://rocks.moonscript.org/modules/peterbillam
so you should be able to install it with the command:

 $ su
 Password:
 # luarocks install --server=http://rocks.moonscript.org fluidsynth

or:

 # luarocks install http://www.pjb.com.au/comp/lua/fluidsynth-1.2-0.rockspec

It depends on the I<fluidsynth> library and its header-files;
for example on Debian you may need:

 # aptitude install libfluidsynth libfluidsynth-dev

or on Centos you may need:

 # yum install fluidsynth-devel

=head1 CHANGES

 20140901 1.6 delete_synth doesn't automatically remove TmpFile
 20140830 1.5 new_player midifilename='-' means stdin
 20140828 1.4 eliminate Settings2numSynths and M.delete_settings
 20140827 1.3 use fluid_get_sysconf, fluid_get_userconf, config file 'set k v'
 20140826 1.2 ~/.config/fluidsynth config file using  k = v
 20140825 1.1 new calling-interface at much higher level
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
