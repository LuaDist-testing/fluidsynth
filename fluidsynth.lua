---------------------------------------------------------------------
--     This Lua5 module is Copyright (c) 2011, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This module is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------

local M = {} -- public interface
M.Version     = '2.0' -- lua5.3, and keep pointers in C arrays
M.VersionDate = '24apr2015'

local ALSA = nil -- not needed if you never use play_event

-- local Synth2settings       = {}  -- 2.0 now identical
-- local AudioDriver2synth    = {}  -- 2.0 now identical
local Player2synth         = {}
local Synth2fastRender     = {}
local ConfigFileSettings   = {}
--local FLUID_FAILED         = -1  -- /usr/include/fluidsynth/misc.h
-- 2.0 all C functions return nil if they fail
local TmpName              = nil -- used to save the C-library's stderr
local DefaultSoundfont     = nil

local Synths               = {}  -- 2.0 indexes into three C arrays
-- local Settingses        = {}  -- 2.0 each synth only has one settings
-- local AudioDrivers      = {}  -- 2.0 each synth only has one audio_driver
local Players              = {}  -- 2.0 indexes into the C array
-- 2.0 each synth has one settings, so Synth2settings is not necessary
-- and each synth has one audio_driver, so AudioDriver2synth is unnecessary
-- but one synth may have multiple midi_players running at the same time
--  (eg: to play several midi files, each starting at a different moment).

-- http://fluidsynth.sourceforge.net/api/
-- http://fluidsynth.sourceforge.net/api/index.html#Sequencer
-- sequencer = new_fluid_sequencer2(0);
-- synthSeqID = fluid_sequencer_register_fluidsynth(sequencer, synth);
-- mySeqID = fluid_sequencer_register_client(sequencer,"me",seq_callback,NULL);
-- seqduration = 1000;  /* ms */
-- delete_fluid_sequencer(sequencer);

-------------------- private utility functions -------------------
local function _debug(s)
	local DEBUG = io.open('/tmp/debug', 'a')
	DEBUG:write(s.."\n")
	DEBUG:close()
end
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
    ['synth.ladspa.active']    = false,  -- LADSPA
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

function first_free_synthnum()     -- 2.0 to keep ptrs in C arrays
	for synthnum = 0,127 do
		if not Synths[synthnum] then
			-- _debug('first_free_synthnum was '..tostring(synthnum))
			return synthnum
		end
	end
	return nil, 'first_free_synthnum: no free synthnums'
end
function first_free_playernum()    -- 2.0 to keep ptrs in C arrays
	for playernum = 0,127 do
		if not Players[playernum] then
			-- _debug('first_free_playernum was '..tostring(playernum))
			return playernum
		end
	end
	return nil, 'first_free_playernum: no free playernums'
end

function new_settings(synthnum)
	TmpName = prv.redirect_stderr()
	local settings = prv.new_fluid_settings(synthnum)
	if settings==nil then return nil,'new_fluid_settings failed' end
	return settings
end

function new_audio_driver(synthnum)
	local audio_driver = prv.new_fluid_audio_driver(synthnum)
	if audio_driver == nil then return nil, M.synth_error(synthnum) end
	return audio_driver
end

function delete_audio_driver(audio_driver)
	local rc = prv.delete_fluid_audio_driver(audio_driver)
	return true
end

function delete_player(player)
	local rc = prv.delete_fluid_player(player)
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

function set(synthnum, key, val)  -- typically called before a synth exists,
	-- but always after its settings have been created
	if type(key) == 'nil' then
		return nil, "fluidsynth: can't set the value for a nil key"
	end
	if type(key) ~= 'string' then
		return nil,"fluidsynth: the setting key "..tostring(key).." has to be a string"
	end
	if type(val) == 'nil' then
		return nil, "fluidsynth: can't set the "..key.." key to nil"
	end
	if type(val) ~= type(DefaultOption[key]) then
		return nil, 'fluidsynth knows no '..key..' setting'
	end
	if key=='synth.sample-rate' or key=='synth.gain' then
		local rc = prv.fluid_settings_setnum(synthnum, key, val)
		if rc == 1 then return true
		else return nil,M.synth_error(synthnum) end
	elseif type(val) == 'number' then
		local rc = prv.fluid_settings_setint(synthnum, key, round(val))
		if rc == 1 then return true
		else return nil,M.synth_error(synthnum) end
	elseif type(val) == 'boolean' then   -- 1.1
		local v = 0
		if val then v = 1 end
		local rc = prv.fluid_settings_setint(synthnum, key, v)
		if rc == 1 then return true
		else return nil,M.synth_error(synthnum) end
	elseif type(val) == 'string' then
		local rc = prv.fluid_settings_setstr(synthnum, key, val)
		if rc == 1 then return true
		else return nil,M.synth_error(synthnum) end
	else
		return nil,'fluidsynth knows no '..key..' setting of '..type(val)..' type'
	end
	return true
end

------------------------ public functions ----------------------

function M.synth_error(synthnum)   -- undocumented
 	-- Get a textual representation of the most recent synth error
	if not synthnum  then return '' end
	return prv.fluid_synth_error(synthnum)
end

function M.error_file_name()   -- so the app can remove it
	return TmpName
end

function M.read_config_file(filename)
	if not filename then
		userconf = prv.fluid_get_userconf()
		sysconf  = prv.fluid_get_sysconf()
		if    is_readable(userconf) then filename = userconf
		elseif is_readable(sysconf) then filename = sysconf
		else return nil, "can't find either "..userconf.." or "..sysconf
		end
	end
	--- 1.7 return not just load but also select commands (eg for drumset)
	local commands = {}
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
			if   string.match(line, '^%s*load%s+%S+')  -- 1.7
			  or string.match(line, '^%s*select%s+%d+') then
				table.insert(commands, line)
			end
		end
	end
	config_file:close()
	return commands
end

function M.new_synth(arg)
	-- "The settings parameter is used directly,
	--  and should not be modified or freed independently."
	if arg == nil then arg = { } end
	local arg_type = type(arg)
	if arg_type ~= 'table' then
		local msg = 'fluidsynth: new_synth arg must be table of settings, not '
		return nil, msg..arg_type
	end
	-- invoking new_synth with a table of settings invokes
	--  new_settings, set, new_synth, new_audio_driver automatically.
	local synthnum = first_free_synthnum()
	local settings = new_settings(synthnum)
	for k,v in pairs(arg) do
		if k ~= 'fast.render' then set(synthnum, k, v) end
	end
	for k,v in pairs(ConfigFileSettings) do
		if k ~= 'fast.render' then set(synthnum, k, v) end
	end
	local synth = prv.new_fluid_synth(synthnum)
	if synth == nil then return nil, 'new_synth() failed' end
	Synths[synthnum] = true
	if arg['fast.render'] then   -- from src/fluidsynth.c
		Synth2fastRender[synthnum] = true
		set(synthnum, 'player.timing-source', 'sample')
		set(synthnum, 'synth.parallel-render', 1)
		-- fast_render should not need this, but currently does
	end
	-- Synth2settings[synth] = settings
	if not Synth2fastRender[synthnum] and arg['audio.driver'] ~= 'none' then
		local audio_driver = new_audio_driver(synthnum)
	end
	--DefaultSoundfont = prv.fluid_settings_copystr(settings,
	-- 'synth.default-soundfont');  NOT SET on my debian stable...
	-- synthnum is no longer an integer cast of a C-pointer, it's an int 0..127
	return synthnum
end

function M.sf_load( synth, commands )
	if type(commands) == 'string' then
		local sf_id = prv.fluid_synth_sfload(synth, filename)
		if sf_id == nil then return nil, M.synth_error(synth)
		else return { sf_id } end
	elseif type(commands) == 'table' then
		--- 1.7 apply not just load but also select commands (eg for drumset)
		local filename2sf_id = {}
		for k,line in ipairs(commands) do
			if string.match(line, '^%s*load%s+%S+') then   -- 1.7
				local filename = string.match(line, '^%s*load%s+(%S+)%s*$')
				if filename and M.is_soundfont(filename) then
					local sf_id = prv.fluid_synth_sfload(synth, filename)
					-- print('filename =',filename, ' sf_id =',sf_id)
					if sf_id==nil then return nil,M.synth_error(synth)
					else filename2sf_id[filename] = sf_id
					end
				end
			elseif string.match(line, '^%s*select%s+%S+') then   -- 1.7
				local cha, sf, bank, patch = string.match(line,
				  '^%s*select%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*$')
					-- print('cha=',cha,'sf=',sf,'bank=',bank,'patch=',patch)
				if cha and sf and bank and patch then
					M.sf_select(synth, cha, sf)
					local bank_select = M.get(synth, 'synth.midi-bank-select')
					if bank_select == 'gs' then   -- 1.8
						M.control_change(synth, cha, 0, bank)
					elseif bank_select == 'xg' then
						M.control_change(synth, cha, 32, bank)
					elseif bank_select == 'mma' then
						local msb = math.floor(bank/128)
						local lsb = bank % 128
						M.control_change(synth, cha,  0, msb)
						M.control_change(synth, cha, 32, lsb)
					-- else warning ?
					end
					M.patch_change(synth, cha, patch)
				else
					return nil, 'config bad format: '..line
				end
			end
		end
		return filename2sf_id
	else
		return nil, "fluidsynth: sf_load 2nd arg must be string or array"
	end
end

function M.sf_select(synth, channel, sf_id)   -- not documented :-(
	local rc = prv.fluid_synth_sfont_select(synth, channel, sf_id)
	if rc == nil then
		return nil, 'sf_select: '..M.synth_error(synth)
	else return true end
end

function M.delete_synth(synth)
	if synth == nil then   -- if synth==nil it deletes all synths
		for synthnum = 0,127 do
			if Synths[synthnum] then
				local rc, msg = M.delete_synth(synthnum)
				if not rc then return rc, msg end
			end
		end
		-- 1.6: os.remove(TmpName) No. See below...
		return true
	end
	Synths[synth] = nil
	-- search though Player2synth deleting any dependent players
	for k,v in pairs(Player2synth) do
		if v == synth then delete_player(k) end
	end
	-- <=1.9 search though AudioDriver2synth deleting dependent audio_drivers
	-- >=2.0 each synth only has one audio_driver, or none if fast_render
	delete_audio_driver(synth)
	local rc = prv.delete_fluid_synth(synth)
	if rc == nil then
		return nil, 'delete_synth: '..M.synth_error(synth)
	end
	-- >=2.0 each synth only has one settings
	prv.delete_fluid_settings(synth)
	-- Synth2settings[synth]   = nil
	Synth2fastRender[synth] = nil
	-- 1.6  if #Synth2settings < 0.5 then os.remove(TmpName) end
	-- No. eg: in fluadity -d, synths get stopped and started.
	return true
end

--------------- functions for playing midi files ----------------

function M.new_player(synth, midifile)
	if not midifile then return nil,'new_player: midifile was nil' end
	local playernum = first_free_playernum()
	local player = prv.new_fluid_player(synth, playernum)
	if player == nil then return nil, M.synth_error(synth) end
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
	if rc == nil then
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
	if rc == nil then return nil, M.synth_error(Player2synth[player])
	else return true end
end

function M.player_join(player)
	-- When should FastRender be invoked ?  Well, it needs knowledge
	-- of the future; it's not quite enough for a player to be running
	-- and for the output to be a wav file, because real-time events
	-- might get fed to the synth while the midi file is playing :-(
	local synth    = Player2synth[player]
	-- local settings = Synth2settings[synth]
	if synth and Synth2fastRender[synth] then  -- just midi->wav
		local rc = prv.fast_render_loop(synth, player)
		return true
	end
	local rc = prv.fluid_player_join(player)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.player_stop(player)
	local rc = prv.fluid_player_stop(player)
	if rc == nil then return nil, M.synth_error(Player2synth[player])
	else
		-- player_play can not be reinvoked ! so just delete_player
		delete_player(player)
		return true
	end
end

function M.player_add_mem(player, buffer)
	local rc = prv.fluid_player_add_mem(player, buffer, string.len(buffer)+1)
	if rc == nil then return nil, M.synth_error(Player2synth[player])
	else return true
	end
end

----------------- functions for playing in real-time -------------

function M.note_on(synth, channel, note, velocity)
	local rc = prv.fluid_synth_noteon(synth, channel, note, velocity)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.note_off(synth, channel, note)
	if note == nil then return nil, 'note_off: argument #3 was nil' end
	local rc = prv.fluid_synth_noteoff(synth, channel, note)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.patch_change(synth, channel, patch)
	local rc = prv.fluid_synth_program_change(synth, channel, patch)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.control_change(synth, channel, cc, val)
	local rc = prv.fluid_synth_cc(synth, channel, cc, val)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.pitch_bend(synth, channel, val) -- val = 0..8192..16383
	local rc = prv.fluid_synth_pitch_bend(synth, channel, val)
	if rc == nil then return nil, M.synth_error(synth)
	else return true end
end

function M.pitch_bend_sens(synth, channel, val) -- val = semitones
	local rc = prv.fluid_synth_pitch_bend_sens(synth, channel, val)
	if rc == nil then return nil, M.synth_error(synth)
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
	return true   -- so assert doesn't die unnecessarily
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

function M.get(synth, key)  -- typically called AFTER the synth exists
	local settings = synth
	if type(key) == 'nil' then
		return nil, "fluidsynth: can't get the value for a nil key"
	end
	if type(key) ~= 'string' then
		return nil,"fluidsynth: the parameter "..tostring(key).." should be a string"
	end
	local val = DefaultOption[key]
	if key=='synth.sample-rate' or key=='synth.gain' then
		local rc = prv.fluid_settings_getnum(settings, key)
		if rc == nil then return nil,M.synth_error(synth) end
		return rc
	elseif type(val) == 'number' then
		local rc = prv.fluid_settings_getint(settings, key)
		if rc == nil then return nil,M.synth_error(synth) end
		return round(rc)
	elseif type(val) == 'boolean' then
		local rc = prv.fluid_settings_getint(settings, key, v)
		if rc == nil then return nil,M.synth_error(synth) end
		if rc == 0 then return false else return true end
	elseif type(val) == 'string' then
		local rc = prv.fluid_settings_copystr(settings, key)
		if rc == nil then return nil,M.synth_error(synth) end
		return rc
	end
	return nil, 'fluidsynth knows no '..key..' setting'
end

---------------------------------------------------------------

return M

