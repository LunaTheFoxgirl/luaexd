// Taken from Derelict-AL
module lua.backend.types;


alias lua_CFunction = int function(lua_State*);

extern (C) nothrow:
alias lua_KFunction = int function(lua_State*, int, lua_KContext);
alias lua_Reader = const(char)* function(lua_State*, void*, size_t*);
alias lua_Writer = int function(lua_State*, const(void)*, size_t, void*);
alias lua_Alloc = void* function(void*, void*, size_t, size_t);

enum LUA_VERSION_MAJOR = "5";
enum LUA_VERSION_MINOR = "3";
enum LUA_VERSION_NUM = 503;
enum LUA_VERSION_RELEASE = "5";

/* option for multiple returns in 'lua_pcall' and 'lua_call' */
enum LUA_MULTRET = -1;

/*
** Pseudo-indices
** (-LUAI_MAXSTACK is the minimum valid index; we keep some free empty
** space after that to help overflow detection)
*/
enum LUA_REGISTRYINDEX = -10000;
enum LUA_ENVIRONINDEX = -10001;
enum LUA_GLOBALSINDEX = -10002;
enum LUAI_MAXSTACK = 15000;
//enum LUA_REGISTRYINDEX = (-LUAI_MAXSTACK - 1000);

//enum lua_upvalueindex!(int i) = (LUA_REGISTRYINDEX - (i));

enum LUA_OK = 0;
enum LUA_YIELD = 1;
enum LUA_ERRRUN = 2;
enum LUA_ERRSYNTAX = 3;
enum LUA_ERRMEM = 4;
enum LUA_ERRGCMM = 5;
enum LUA_ERRERR = 6;

struct lua_State;

/*
** basic types
*/
enum LUA_TNONE = -1;

enum LUA_TNIL = 0;
enum LUA_TBOOLEAN = 1;
enum LUA_TLIGHTUSERDATA = 2;
enum LUA_TNUMBER = 3;
enum LUA_TSTRING = 4;
enum LUA_TTABLE = 5;
enum LUA_TFUNCTION = 6;
enum LUA_TUSERDATA = 7;
enum LUA_TTHREAD = 8;

enum LUA_NUMTAGS = 9;

/* minimum Lua stack available to a C function */
enum LUA_MINSTACK = 20;

/* predefined values in the registry */
enum LUA_RIDX_MAINTHREAD = 1;
enum LUA_RIDX_GLOBALS = 2;
enum LUA_RIDX_LAST = LUA_RIDX_GLOBALS;

/* type of numbers in Lua */
alias LUA_NUMBER = double;

alias LUA_INTEGER = ptrdiff_t;
alias LUA_UNSIGNED = uint;
alias LUA_KCONTEXT = ptrdiff_t;

alias lua_Number = LUA_NUMBER;

alias lua_Integer = LUA_INTEGER;
alias lua_Unsigned = LUA_UNSIGNED;
alias lua_KContext = LUA_KCONTEXT;

// luaL
enum LUA_NOREF = -2;
enum LUA_REFNIL = -1;

__gshared const(char)[] lua_ident;

enum LUA_OPADD = 0; /* ORDER TM, ORDER OP */
enum LUA_OPSUB = 1;
enum LUA_OPMUL = 2;
enum LUA_OPMOD = 3;
enum LUA_OPPOW = 4;
enum LUA_OPDIV = 5;
enum LUA_OPIDIV = 6;
enum LUA_OPBAND = 7;
enum LUA_OPBOR = 8;
enum LUA_OPBXOR = 9;
enum LUA_OPSHL = 10;
enum LUA_OPSHR = 11;
enum LUA_OPUNM = 12;
enum LUA_OPBNOT = 13;

enum LUA_OPEQ = 0;
enum LUA_OPLT = 1;
enum LUA_OPLE = 2;

enum LUA_GCSTOP = 0;
enum LUA_GCRESTART = 1;
enum LUA_GCCOLLECT = 2;
enum LUA_GCCOUNT = 3;
enum LUA_GCCOUNTB = 4;
enum LUA_GCSTEP = 5;
enum LUA_GCSETPAUSE = 6;
enum LUA_GCSETSTEPMUL = 7;
enum LUA_GCISRUNNING = 9;

/* Key to file-handle type */
enum LUA_FILEHANDLE = "FILE*";
enum LUA_COLIBNAME = "coroutine";
enum LUA_TABLIBNAME = "table";
enum LUA_IOLIBNAME = "io";
enum LUA_OSLIBNAME = "os";
enum LUA_STRLIBNAME = "string";
enum LUA_MATHLIBNAME = "math";
enum LUA_DBLIBNAME = "debug";
enum LUA_LOADLIBNAME = "package";

struct luaL_Reg {
    const(char)* name;
    lua_CFunction func;
}
