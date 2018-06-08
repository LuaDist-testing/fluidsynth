/*
    C-fluidsynth.c - fluidsynth bindings for Lua

   This Lua5 module is Copyright (c) 2014, Peter J Billam
                     www.pjb.com.au

 This module is free software; you can redistribute it and/or
       modify it under the same terms as Lua5 itself.
*/

#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
#include <string.h>   /* for bcopy, memcopy */
#include <unistd.h>   /* for dup, dup2; perhaps isatty */

/* ----------- from http://fluidsynth.sourceforge.net/api/ ---------- */
#include <fluidsynth.h>
/* http://fluidsynth.sourceforge.net/api/example.c-example.html
   http://fluidsynth.sourceforge.net/api/fluidsynth__arpeggio.c-example.html
   http://fluidsynth.sourceforge.net/api/fluidsynth__fx.c-example.html
   http://fluidsynth.sourceforge.net/api/fluidsynth__metronome.c-example.html
   http://fluidsynth.sourceforge.net/api/fluidsynth__simple.c-example.html
   http://en.wikipedia.org/wiki/Sizeof
   http://en.wikipedia.org/wiki/Sizeof#sizeof_and_incomplete_types
*/

/* fprintf("C: FLUID_OK = %d\n",FLUID_OK); should be defined in misc.h, no? */

/* FILE * tmpfile (void) declared in stdio.h.
   char * tmpnam (char *result)
    Warning: Between the time the pathname is constructed and the file is
    created another process might have created a file with the same name
    using tmpnam, leading to a possible security hole. The implementation
    generates names which can hardly be predicted, but when opening the file
    you should use the O_EXCL flag. Using tmpfile or mkstemp is a safe way
    to avoid this problem.
    But how do I use that in a freopen context ?
    not: dup2(fileno(stderr), fileno(tmpfile()));  :-(
*/
int save_stderr = -1;
fluid_synth_t* synths[128] = { 0 };   /* 2.0 to keep ptrs inside the C code */
fluid_settings_t* settingses[128] = { 0 };     /* 2.0 to keep ptrs inside C */
fluid_player_t* players[128] = { 0 }; /* 2.0 to keep ptrs inside the C code */
fluid_audio_driver_t* audio_drivers[128] = { 0 };  /* 2.0 to keep ptrs in C */

static int c_redirect_stderr(lua_State *L) {
	save_stderr = dup(fileno(stderr));
	char* tmp_file = tmpnam(NULL);
	freopen(tmp_file, "w", stderr);
	/* The C library function FILE *freopen(const char *filename,
	   const char *mode, FILE *stream) associates a new filename with the
	   given open stream and same time closing the old file in stream.
	*/
   	lua_pushstring(L, tmp_file);
	return 1;
}
static int c_restore_stderr() {
	dup2(save_stderr, fileno(stderr));
	close(save_stderr);
	save_stderr = -1;
	return 0;
}

static int c_new_fluid_settings(lua_State *L) {  /* synthnum */
	int               synthnum = (int)(int)luaL_checkinteger(L, 1);
	fluid_settings_t* settings = new_fluid_settings();  /* api */
	/* redirect_stderr is called from lua so fluidsynth knows tmp_file */
	settingses[synthnum] = settings;
	lua_pushinteger(L, synthnum); 
	return 1;
}

static int c_delete_fluid_settings(lua_State *L) {  /* settingsnum */
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	delete_fluid_settings(settings);   /* void; returns nothing */
	if (save_stderr != -1) { c_restore_stderr(); }
   	lua_pushinteger(L, 0);   /* FLUID_OK */
	return 1;
}

static int c_fluid_settings_setint(lua_State *L) {  /* settingsnum,key,val */
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char *key = lua_tostring(L, 2);
	lua_Integer val = lua_tointeger(L, 3);
    int rc = fluid_settings_setint(settings, key, val);
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_settings_setnum(lua_State *L) {  /* settings,key,val */
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char *key = lua_tostring(L, 2);
	lua_Number  val = lua_tonumber(L, 3);
    int rc = fluid_settings_setnum(settings, key, val);
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_settings_setstr(lua_State *L) {  /* settings,key,val */
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char *key = lua_tostring(L, 2);
	const char *val = lua_tostring(L, 3);
    int rc = fluid_settings_setstr(settings, key, val);
   	lua_pushinteger(L, rc);
	return 1;
}

/* http://fluidsynth.sourceforge.net/api/synth_8h.html */
static int c_new_fluid_synth(lua_State *L) {  /* synthnum */
	int               synthnum = (int)luaL_checkinteger(L, 1);
	fluid_settings_t* settings = settingses[synthnum];
	fluid_synth_t*    synth    = new_fluid_synth(settings);
	if ((long int)synth == FLUID_FAILED) { lua_pushnil(L); return 1; }
	synths[synthnum] = synth;
    lua_pushinteger(L, synthnum); 
    return 1;
}

static int c_delete_fluid_synth(lua_State *L) {  /* synthnum */
	/* fluid_settings_t* settings = (fluid_settings_t*)lua_tointeger(L, 1); */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	int rc = delete_fluid_synth(synth);
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_new_fluid_audio_driver(lua_State *L) {  /* synthnum */
	int               synthnum = (int)luaL_checkinteger(L, 1);
	fluid_synth_t*    synth    = synths[synthnum];
	fluid_settings_t* settings = settingses[synthnum];
	fluid_audio_driver_t* audio_driver=new_fluid_audio_driver(settings,synth);
	if ((long int)audio_driver == FLUID_FAILED) { lua_pushnil(L); return 1; }
	audio_drivers[synthnum] = audio_driver;
    lua_pushinteger(L, synthnum);
	return 1;
}

static int c_delete_fluid_audio_driver(lua_State *L) {  /* audio_driver */
	int               synthnum = (int)luaL_checkinteger(L, 1);
	fluid_audio_driver_t* audio_driver = audio_drivers[synthnum];
	if (audio_driver) {  /* 2.0 absent AudioDriver2synth, must defend */
		delete_fluid_audio_driver(audio_driver);   /* returns nothing */
		audio_drivers[synthnum] = 0;
	}
	return 0;
}

static int c_new_fluid_player(lua_State *L) {  /* synthnum,playernum */
	int           synthnum = (int)luaL_checkinteger(L, 1);
	int          playernum = (int)luaL_checkinteger(L, 2);
	fluid_synth_t*  synth  = synths[synthnum];
	fluid_player_t* player = new_fluid_player(synth);
	if ((long int)player == FLUID_FAILED) { lua_pushnil(L); return 1; }
	players[playernum] = player;
	lua_pushinteger(L, playernum);
	return 1;
}

static int c_delete_fluid_player(lua_State *L) {  /* playernum */
	int              playernum = (int)luaL_checkinteger(L, 1);
	fluid_player_t* player = players[playernum];
	delete_fluid_player(player);   /* always returns FLUID_OK */
	players[playernum] = 0;
	return 1;
}

/*
SoundFonts are loaded with the fluid_synth_sfload() function. The function
takes the path to a SoundFont file and a boolean to indicate whether
the presets of the MIDI channels should be updated after the SoundFont
is loaded. When the boolean value is TRUE, all MIDI channel bank and
program numbers will be refreshed, which may cause new instruments to
be selected from the newly loaded SoundFont.

The synthesizer can load any number of SoundFonts. The loaded SoundFonts
are treated as a stack, where each new loaded SoundFont is placed at the
top of the stack. When selecting presets by bank and program numbers,
SoundFonts are searched beginning at the top of the stack. In the case
where there are presets in different SoundFonts with identical bank and
program numbers, the preset from the most recently loaded SoundFont is
used. The fluid_synth_program_select() can be used for unambiguously
selecting a preset or bank offsets could be applied to each SoundFont
with fluid_synth_set_bank_offset(), to try and ensure that each preset
has unique bank and program numbers.

The fluid_synth_sfload() function returns the unique identifier of the
loaded SoundFont, or -1 in case of an error. This identifier is used
in subsequent management functions: fluid_synth_sfunload() removes the
SoundFont, fluid_synth_sfreload() reloads the SoundFont. When a SoundFont
is reloaded, it retains it's ID and position on the SoundFont stack.

Additional API functions are provided to get the number of loaded
SoundFonts and to get a pointer to the SoundFont.

Sending MIDI Events
Once the synthesizer is up and running and a SoundFont is loaded,
most people will want to do something useful with it. Make noise, for
example. MIDI messages can be sent using the fluid_synth_noteon(),
fluid_synth_noteoff(), fluid_synth_cc(), fluid_synth_pitch_bend(),
fluid_synth_pitch_wheel_sens(), and fluid_synth_program_change() functions.
For convenience, there's also a fluid_synth_bank_select() function (the
bank select message is normally sent using a control change message).
*/
static int c_fluid_synth_error(lua_State *L) {  /* synth */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	char* msg = fluid_synth_error(synth);
   	lua_pushstring(L, msg);
	return 1;
}

static int c_fluid_synth_sfload(lua_State *L) {  /* synth,filename,reassign */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	const char* filename = lua_tostring(L, 2);
	int reassign_presets = lua_toboolean(L, 3);
	int rc = fluid_synth_sfload(synth, filename, reassign_presets);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_sfont_select(lua_State *L) {  /* synth,cha,sfid */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer channel = lua_tointeger(L, 2);
	lua_Integer sf_id   = lua_tointeger(L, 3);
	int rc = fluid_synth_sfont_select(synth, channel, sf_id);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_player_add(lua_State *L) {  /* player,midifilename */
	fluid_player_t* player = players[lua_tointeger(L, 1)];
	const char* filename = lua_tostring(L, 2);
	int rc = fluid_player_add(player, filename);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, rc);
	return 1;
}
static int c_fluid_player_play(lua_State *L) {  /* playernum */
	fluid_player_t* player = players[lua_tointeger(L, 1)];
	int rc = fluid_player_play(player);
   	lua_pushinteger(L, rc);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, rc);
	return 1;
}
/*
sourceforge.net/p/fluidsynth/code-git/ci/master/tree/fluidsynth/src/fluidsynth.c
*/
static int c_fast_render_loop(lua_State *L) {
	fluid_synth_t*       synth = synths[lua_tointeger(L, 1)];
	fluid_player_t*     player = players[lua_tointeger(L, 2)];
	fluid_file_renderer_t* renderer = new_fluid_file_renderer (synth);
	if (!renderer) return 0;
	while (fluid_player_get_status(player) == FLUID_PLAYER_PLAYING) {
/*
   fluidsynth: error:
     fluid_rvoice_event_dispatch: Unknown method (nil) to dispatch!
   printf("FLUID_PLAYER_PLAYING = %d\n",FLUID_PLAYER_PLAYING);
   Should usleep here for 0.1 sec or so, no ?
*/
		if (fluid_file_renderer_process_block(renderer) != FLUID_OK) { break; }
	}
	delete_fluid_file_renderer(renderer);
   	lua_pushboolean(L, 1);
	return 1;
} 
static int c_fluid_player_join(lua_State *L) {  /* player */
	fluid_player_t* player = players[lua_tointeger(L, 1)];
	int rc = fluid_player_join(player);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, rc);
	return 1;
}
static int c_fluid_player_stop(lua_State *L) {  /* player */
	fluid_player_t* player = players[lua_tointeger(L, 1)];
	int rc = fluid_player_stop(player);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_program_change(lua_State *L) { /* synth,cha,patch */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer channel = lua_tointeger(L, 2);
	lua_Integer program = lua_tointeger(L, 3);
	int rc = fluid_synth_program_change(synth, channel, program);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_cc(lua_State *L) { /* synth,cha,cc,val */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer cha = lua_tointeger(L, 2);
	lua_Integer cc  = lua_tointeger(L, 3);
	lua_Integer val = lua_tointeger(L, 4);
	int rc = fluid_synth_cc(synth, cha, cc, val);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_noteon(lua_State *L) { /* synth,cha,note,vel */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	int cha  = lua_tointeger(L, 2);
	int note = lua_tointeger(L, 3);
	int vel  = lua_tointeger(L, 4);
	int rc = fluid_synth_noteon(synth, cha, note, vel);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_noteoff(lua_State *L) {  /* synth,cha,note */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer cha  = lua_tointeger(L, 2);
	lua_Integer note = lua_tointeger(L, 3);
	int rc = fluid_synth_noteoff(synth, cha, note);
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
   	lua_pushinteger(L, rc);
	return 1;
}

static int c_fluid_synth_pitch_bend(lua_State *L) { /* synth,cha,val=0-16383 */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer cha  = lua_tointeger(L, 2);
	lua_Integer val  = lua_tointeger(L, 3);
	int rc = fluid_synth_pitch_bend(synth, cha, val);
   	lua_pushinteger(L, rc);  /* FLUID_OK or FLUID_FAILED */
	if (rc == FLUID_FAILED) { lua_pushnil(L); return 1; }
	return 1;
}

static int c_fluid_synth_pitch_bend_sens(lua_State *L) { /* synth,cha,val */
	fluid_synth_t* synth = synths[(int)luaL_checkinteger(L, 1)];
	lua_Integer cha  = lua_tointeger(L, 2);
	lua_Integer val  = lua_tointeger(L, 3);
	/* pitch wheel semi-range in semitones, default 2 semitones
	   not present in 1.1.5-2
	   int rc = fluid_synth_pitch_bend_sens(synth, cha, val);
	*/
   	lua_pushnil(L);
	return 1;
}

static int c_fluid_is_soundfont(lua_State *L) { /* filename */
	const char* filename = lua_tostring(L, 1);
	lua_pushboolean(L, fluid_is_soundfont(filename));
	return 1;
}

static int c_fluid_is_midifile(lua_State *L) { /* filename */
	const char* filename = lua_tostring(L, 1);
	lua_pushboolean(L, fluid_is_midifile(filename));
	return 1;
}

static int c_fluid_get_sysconf(lua_State *L) { /* fluidsynth/shell.h */
	const int length = 1024;
	char *buffer = malloc(length);
/* warning: incompatible implicit declaration of built-in function ‘malloc’ */
	lua_pushstring(L, fluid_get_sysconf(buffer, length));
	return 1;
}

static int c_fluid_get_userconf(lua_State *L) { /* fluidsynth/shell.h */
	const int length = 1024;
	char *buffer = malloc(length);
/* warning: incompatible implicit declaration of built-in function ‘malloc’ */
	lua_pushstring(L, fluid_get_userconf(buffer, length));
	return 1;
}

static int c_fluid_player_add_mem(lua_State *L) { /* fluidsynth/midi.h */
	/* (fluid_player_t* player, const void *buffer, size_t len) */
	fluid_player_t* player = players[lua_tointeger(L, 1)];
	const char *buffer = lua_tostring(L, 2);
/* http://stackoverflow.com/questions/5547131/c-question-const-void-vs-void */
	size_t length = (size_t)lua_tointeger(L, 3);
	lua_pushinteger(L, fluid_player_add_mem(player, buffer, length));
	/* returns void */
	lua_pushboolean(L, 1);
	return 1;
}

static int c_fluid_settings_copystr(lua_State *L) {
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char* key = lua_tostring(L, 2);
	const int length = 1024;
	char *buffer = malloc(length);
	int rc = fluid_settings_copystr(settings, key, buffer, length);
	if (rc) { lua_pushstring(L,buffer); } else { lua_pushnil(L); }
	return 1;
}

static int c_fluid_settings_getnum(lua_State *L) {
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char* key = lua_tostring(L, 2);
	lua_Number val = 0.0;
	int rc = fluid_settings_getnum(settings, key, &val);
	if (rc) { lua_pushnumber(L,val); } else { lua_pushnil(L); }
	return 1;
}

static int c_fluid_settings_getint(lua_State *L) {
	fluid_settings_t* settings = settingses[(int)luaL_checkinteger(L, 1)];
	const char* key = lua_tostring(L, 2);
	int         val = 0;
	int rc = fluid_settings_getint(settings, key, &val);
	if (rc) { lua_pushinteger(L,val); } else { lua_pushnil(L); }
	return 1;
}

/*static int c_fluid_settings_getstr_default(lua_State *L) {
	fluid_settings_t* settings = (fluid_settings_t*)lua_tointeger(L, 1);
	const char* key = lua_tostring(L, 2);
	lua_pushstring(L, fluid_settings_getstr_default(settings, key));
	return 1;
}*/

/* ----------------- evolved from C-midialsa.c ---------------- */
struct constant {  /* Gems p. 334 */
	const char * name;
	int value;
};
static const struct constant constants[] = {
	/* {"Version", Version}, */
	/* {"FLUID_OK",                   FLUID_OK}, misc.h ?? */
	{NULL, 0}
};

static const luaL_Reg prv[] = {  /* private functions */
    {"new_fluid_settings",         c_new_fluid_settings},
    {"fluid_settings_setint",      c_fluid_settings_setint},
    {"fluid_settings_setnum",      c_fluid_settings_setnum},
    {"fluid_settings_setstr",      c_fluid_settings_setstr},
    {"new_fluid_synth",            c_new_fluid_synth},
    {"new_fluid_audio_driver",     c_new_fluid_audio_driver},
    {"delete_fluid_synth",         c_delete_fluid_synth},
    {"delete_fluid_audio_driver",  c_delete_fluid_audio_driver},
    {"delete_fluid_settings",      c_delete_fluid_settings},
	{"fluid_synth_sfload",         c_fluid_synth_sfload},
	{"fluid_synth_error",          c_fluid_synth_error},
	{"fluid_synth_sfont_select",   c_fluid_synth_sfont_select},
	{"fluid_synth_program_change", c_fluid_synth_program_change},
	{"fluid_synth_cc",             c_fluid_synth_cc},
	{"fluid_synth_noteon",         c_fluid_synth_noteon},
	{"fluid_synth_noteoff",        c_fluid_synth_noteoff},
	{"fluid_synth_pitch_bend",     c_fluid_synth_pitch_bend},
    {"new_fluid_player",           c_new_fluid_player},
    {"fluid_player_add",           c_fluid_player_add},
    {"fluid_player_play",          c_fluid_player_play},
    {"fast_render_loop",           c_fast_render_loop},
    {"fluid_player_join",          c_fluid_player_join},
    {"fluid_player_stop",          c_fluid_player_stop},
    {"delete_fluid_player",        c_delete_fluid_player},
    {"fluid_is_soundfont",         c_fluid_is_soundfont},
    {"fluid_is_midifile",          c_fluid_is_midifile},
    {"redirect_stderr",            c_redirect_stderr},
    {"restore_stderr",             c_restore_stderr},
    {"fluid_get_sysconf",          c_fluid_get_sysconf},
    {"fluid_get_userconf",         c_fluid_get_userconf},
    {"fluid_player_add_mem",       c_fluid_player_add_mem},
    {"fluid_settings_copystr",     c_fluid_settings_copystr},
    {"fluid_settings_getnum",      c_fluid_settings_getnum},
    {"fluid_settings_getint",      c_fluid_settings_getint},
	/* {"fluid_synth_pitch_bend_sens",c_fluid_synth_pitch_bend_sens}, */
    {NULL, NULL}
};

static int initialise(lua_State *L) {  /* Lua Programming Gems p. 335 */
    /* Lua stack: aux table, prv table, dat table */
    int index;  /* define constants in module namespace */
    for (index = 0; constants[index].name != NULL; ++index) {
        lua_pushinteger(L, constants[index].value);
        lua_setfield(L, 3, constants[index].name);
    }
    /* lua_pushvalue(L, 1);   * set the aux table as environment */
    /* lua_replace(L, LUA_ENVIRONINDEX);
       unnecessary here, fortunately, because it fails in 5.2 */
    lua_pushvalue(L, 2); /* register the private functions */
#if LUA_VERSION_NUM >= 502
    luaL_setfuncs(L, prv, 0);    /* 5.2 */
    return 0;
#else
    luaL_register(L, NULL, prv); /* 5.1 */
    return 0;
#endif
}

int luaopen_fluidsynth(lua_State *L) {
    lua_pushcfunction(L, initialise);
    return 1;
}

