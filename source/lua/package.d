module lua;
public import lua.backend.types;
import lua.backend;
import std.string;
import std.traits;
import std.conv;
import std.variant;

public:
private __gshared bool isInitialized;

alias LuaStateFunction = lua_CFunction;
alias LuaStatePtr = lua_State*;

__gshared string LUA_PATH = "content/scripts/?.lua";

/// Expose this to Lua via LuaUserData
struct Expose;

/// Expose this to function to lua via auto-generated getters/setters
struct ExposeFunction;

class LuaException : Exception {
public:
    this(string message, string origin) {
        super("<%s> from %s".format(message, origin));
    }
}

/// Gets a new Lua state.
LuaState newState() {
    import std.process;

    // Make sure that lua is only loaded once in to memory.
    if (!isInitialized) {
        bool loaded = loadLua();
    }

    lua_State* sptr = luaL_newstate();

    environment["LUA_PATH"] = LUA_PATH;
    // Bind lua libs
    // Sandbox away potentially dangerous stuff for now.
    /*luaopen_base(sptr);
    luaopen_string(sptr);
    luaopen_math(sptr);
    luaopen_table(sptr);

    // This only works via lua calls ¯\_(ツ)_/¯
    // Tbh this might be a little dangerous, but its what i can do rn.
    // Also pushcfunction doesn't take extern(C) elements so we do some dumb casting.
    lua_pushcfunction(sptr, cast(LuaStateFunction) luaopen_package);
    lua_pushliteral(sptr, LUA_LOADLIBNAME);

    // This is named wrong but w/e
    luaL_call(sptr, 1, 0);*/
    luaL_openlibs(sptr);
    return new LuaState(sptr);
}

/// Disposes lua from memory, run on exit.
/// or not, whatever floats your goat.
void disposeLua() {
    unloadLua();
}

enum IsInteger(T) = (is(typeof(T) == byte) || is(typeof(T) == short)
            || is(typeof(T) == int) || is(typeof(T) == long) || is(typeof(T) == lua_Integer));
enum IsNumber(T) = (is(typeof(T) == float) || is(typeof(T) == double) || is(typeof(T) == lua_Number));
enum IsBoolean(T) = (is(typeof(T) == bool));
enum IsUnsigned(T) = (is(typeof(T) == ubyte) || is(typeof(T) == ushort)
            || is(typeof(T) == uint) || is(T : ulong) || is(typeof(T) == lua_Unsigned));
enum IsKContext(T) = (is(typeof(T) == ptrdiff_t) || is(typeof(T) == lua_KContext));
enum IsString(T) = (is(T : string) || is(typeof(T) == const(char)*));
enum IsFunction(T) = (is(T : lua_CFunction) || is(T : LuaStateFunction));

Variant stackToVariant(LuaState state) {
    return stackToVariant(state.state);
}

Variant stackToVariant(lua_State* state) {
    immutable(int) type = lua_type(state, -1);
    Variant x;
    switch (type) {
    case (LUA_TBOOLEAN):
        x = lua_toboolean(state, -1);
        break;
    case (LUA_TLIGHTUSERDATA):
        x = lua_touserdata(state, -1);
        break;
    case (LUA_TNUMBER):
        x = lua_tonumber(state, -1);
        break;
    case (LUA_TSTRING):
        x = lua_tostring(state, -1).text;
        break;
    default:
        lua_pop(state, 1);
        break;
    }
    return x;
}

private void g_push(T)(lua_State* state, T value) {
    static if (IsUnsigned!T) {
        lua_pushinteger(state, cast(lua_Unsigned) value);
    } else static if (IsInteger!T) {
        lua_pushinteger(state, cast(lua_Integer) value);
    } else static if (IsNumber!T) {
        lua_pushnumber(state, cast(lua_Number) value);
    } else static if (IsBoolean!T) {
        lua_pushboolean(state, cast(int) value);
    } else static if (IsString!T) {
        lua_pushstring(state, toStringz(value));
    } else static if (IsFunction!T) {
        lua_pushcfunction(state, cast(lua_CFunction) value);
    } else {
        lua_pushlightuserdata(state, value);
    }
}

private T g_pop(T)(lua_State* state) {
    static if (IsUnsigned!T) {
        return cast(T) lua_tointeger(state, -1);
    } else static if (IsInteger!T) {
        return cast(T) lua_tointeger(state, -1);
    } else static if (IsNumber!T) {
        return cast(T) lua_tonumber(state, -1);
    } else static if (IsBoolean!T) {
        return cast(T) lua_toboolean(state, -1);
    } else static if (IsString!T) {
        return lua_tostring(state, -1).text;
    } else static if (IsFunction!T) {
        return lua_tocfunction(state.state, -1);
    } else {
        return cast(T) lua_touserdata(state, -1);
    }
}

mixin template luaTableDef() {
    lua_State* state;

    void push(T)(T value) {
        return g_push!T(state, value);
    }

    T pop(T)() {
        return g_pop!T(state);
    }
}

class LuaRegistry {
private:
    mixin luaTableDef;

    this(LuaState state) {
        this(state.state);
    }

    this(lua_State* state) {
        this.state = state;
    }

public:
    void set(T, TX)(TX id, T value) {
        push!TX(id);
        push!T(value);
        lua_settable(state, LUA_REGISTRYINDEX);
    }

    T get(T, TX)(TX id) {
        push!TX(id);
        lua_gettable(state, LUA_REGISTRYINDEX);
        return pop!T;
    }

    LuaTable newTable(string name) {
        return new LuaTable(state, name, true, false);
    }
}

/// A temporary table which will can set set in a function
/// You can only set values in this table, not get them.
class LuaLocalTable {
private:
    mixin luaTableDef;
public:
    this(LuaState state) {
        this(state.state);
    }

    this(lua_State* state) {
        import std.stdio;

        this.state = state;

        // create table.
        lua_newtable(this.state);
    }

    void set(T, TX)(T id, TX value) {
        import std.stdio;

        //push!string(id.text);

        push!TX(value);
        lua_setfield(state, -2, toStringz(id.text));

        /*writeln("lua_settable");
        lua_settable(state, -3);*/
    }

    void setTable(int id) {
        lua_settable(state, id);
    }

    void setMetaTable(int id) {
        lua_setmetatable(state, id);
    }

    void bindMetatable(LuaMetaTable table) {
        table.setMetatable();
    }
}

class LuaMetaTable {
private:
    mixin luaTableDef;
    string name;

public:
    this(LuaState state, string name) {
        this(state.state, name);
    }

    this(lua_State* state, string name) {
        this.state = state;
        this.name = name;

        // create table.
        luaL_newmetatable(this.state, toStringz(name));
    }

    /// metatable shenannigans
    void setMetatable(int id = -3) {
        import std.stdio;

        push!string(name);
        lua_gettable(state, LUA_REGISTRYINDEX);
        lua_setmetatable(state, id);
    }

    // pushes this to the lua stack
    void toStack() {
        lua_gettable(state, LUA_REGISTRYINDEX);
    }

    void set(T, TX)(T id, TX value) {
        //push!T(id);
        push!TX(value);
        lua_setfield(state, -2, toStringz(id.text));
        //lua_settable(state, -3);
    }
}

/// A lua table.
class LuaTable {
private:
    mixin luaTableDef;
    string name;
    string isMetatableTo = null;
    immutable(char)* nameRef;

    bool parentRegistry;

    this(lua_State* state) {
        this.state = state;
    }

    this(lua_State* state, string name, bool parentRegistry = false, bool exists = false) {
        this(state);
        name = name;
        nameRef = toStringz(name);
        parentRegistry = parentRegistry;

        if (!parentRegistry) {
            // create table.
            if (!exists) {
                lua_newtable(this.state);
                lua_setglobal(this.state, nameRef);
            } else {
                lua_getglobal(this.state, nameRef);
            }
        } else {
            lua_newtable(this.state);
            if (!exists) {
                push!string(name);
                lua_newtable(this.state);
                lua_settable(state, LUA_REGISTRYINDEX);
            } else {
                push!string(name);
                lua_gettable(state, LUA_REGISTRYINDEX);
            }
        }
    }

public:
     ~this() {
        if (!parentRegistry) {
            // push this table to the stack.
            lua_getglobal(state, nameRef);
        } else {
            push!string(name);
            lua_gettable(state, LUA_REGISTRYINDEX);
        }

        lua_pushnil(state);
        lua_settable(state, -2);
    }

    this(LuaState state, string name, bool exists = false) {
        this(state.state, name, exists);
    }

    void set(T)(int id, T value) {
        if (isMetatableTo !is null) {
            throw new Exception("Please restore metatable before modifying");
        }
        if (!parentRegistry) {
            // push this table to the stack.
            lua_getglobal(state, nameRef);
        } else {
            push!string(name);
            lua_gettable(state, LUA_REGISTRYINDEX);
        }

        lua_pushinteger(state, id);

        push!T(value);

        lua_settable(state, -3);
    }

    void set(T)(string name, T value) {
        if (isMetatableTo !is null) {
            throw new Exception("Please restore metatable before modifying");
        }
        if (!parentRegistry) {
            // push this table to the stack.
            lua_getglobal(state, nameRef);
        } else {
            push!string(name);
            lua_gettable(state, LUA_REGISTRYINDEX);
        }

        lua_pushstring(state, toStringz(name));

        push!T(value);

        lua_settable(state, -3);
    }

    T get(T)(int id) {
        if (isMetatableTo !is null) {
            throw new Exception("Please restore metatable before modifying");
        }
        if (!parentRegistry) {
            // push this table to the stack.
            lua_getglobal(state, nameRef);
        } else {
            push!string(name);
            lua_gettable(state, LUA_REGISTRYINDEX);
        }

        // push value to stack and convert it.
        lua_rawgeti(state, -1, id);
        T p = pop!T(state);

        // Pop value on stack and return.
        lua_pop(state, 2);
        return p;
    }

    T get(T)(string name) {
        if (isMetatableTo !is null) {
            throw new Exception("Please restore metatable before modifying");
        }
        if (!parentRegistry) {
            // push this table to the stack.
            lua_getglobal(state, nameRef);
        } else {
            push!string(name);
            lua_gettable(state, LUA_REGISTRYINDEX);
        }

        // push value to stack and convert it.
        lua_getfield(state, -1, toStringz(name));
        T p = pop!T;

        // Pop value on stack and return.
        lua_pop(state, 2);
        return p;

    }

    // pushes this to the lua stack
    void toStack() {
        lua_getglobal(state, nameRef);
    }

    /// Deletes this table from global space and sets it as metatable to another table
    void metatableTo(LuaTable table) {
        lua_getglobal(state, table.nameRef);
        lua_getglobal(state, nameRef);
        lua_setmetatable(state, -2);
        lua_setglobal(state, table.nameRef);

        // Remove old table ref
        lua_pushnil(state);
        lua_setglobal(state, nameRef);

        isMetatableTo = table.name;
    }

    void bindMetatable(LuaMetaTable table) {
        lua_getglobal(state, nameRef);
        table.setMetatable();
    }

    /// restores this table in to global scope.
    void restoreThis() {
        if (isMetatableTo !is null) {
            throw new Exception("This table is not bound.");
        }

        lua_getglobal(state, toStringz(isMetatableTo));
        if (lua_getmetatable(state, -1) > 0) {
            lua_setglobal(state, nameRef);

            // Now remove the old table.
            lua_getglobal(state, toStringz(isMetatableTo));
            lua_pushnil(state);
            lua_setmetatable(state, -2);

            isMetatableTo = null;
        } else {
            throw new Exception("Metatable seems to have been removed outside of scope.");
        }
    }
}

class LuaThread {
private:
    lua_State* state;
    LuaState parent;

    this(LuaState parent) {
        this.parent = parent;
    }

public:
     ~this() {
        lua_close(state);
    }

    /// Executes a string as lua code in the thread.
    void executeString(string code, string name = "unnamed") {
        if (luaL_dostring(state, toStringz(code)) != LUA_OK) {
            throw new LuaException(lua_tostring(state, -1).text, name);
        }
        lua_close(state);
    }
}

mixin template luaImpl(T) {

    import std.traits;
    import lua.backend;
    import std.conv;
    import std.string;
    import std.variant;

    mixin luaImplFuncs!T;

    static LuaStateFunction __new = (state) {

        // constructor begin
        Variant[] params;
        immutable(int) stack = lua_gettop(state);
        foreach (i; 1 .. stack) {
            import std.stdio;

            params ~= stackToVariant(state);
            lua_pop(state, stack);
        }

        // Instantiate T.
        static if (is(T == struct)) {
            T* tInstance = new T;
            tInstance.instantiate(params);
        } else {
            T tInstance = new T;
            tInstance.instantiate(params);
        }

        // Create local table.
        LuaLocalTable mainTable = new LuaLocalTable(state);
        int mtabId = lua_gettop(state);

        mainTable.set!(string, T*)("selfPtr", tInstance);

        // Trait dark magic hide your children.
        static foreach (element; __traits(derivedMembers, T)) {

            // Make sure only public members are considered
            static if (__traits(compiles, __traits(getMember, T, element))) {

                // Make sure it's an exposed function.
                static if (hasUDA!(__traits(getMember, T, element), ExposeFunction)) {

                    // bind functions.
                    mixin(q{mainTable.set!(string, LuaStateFunction)("%s", __lua_%s_call_%s);}.format(element,
                            T.stringof, element));

                }
            }
        }

        LuaMetaTable metaTable = new LuaMetaTable(state, "A");
        int mttabId = lua_gettop(state);

        metaTable.set!(string, LuaStateFunction)("__index", __index);
        metaTable.set!(string, LuaStateFunction)("__newindex", __newindex);
        metaTable.setMetatable();
        lua_pop(state, 1);

        return 1;
    };

    // __index function
    static LuaStateFunction __index = (state) {

        // Index.
        string index = lua_tostring(state, -1).text;

        if (index != "selfPtr") {
            // get self pointer
            lua_pushstring(state, toStringz("selfPtr"));
            lua_rawget(state, 1);

            // self pointer.
            T* tPtr = (cast(T*) lua_touserdata(state, -1));
            lua_pop(state, 1);

            // Trait dark magic hide your children.
            static foreach (element; __traits(derivedMembers, T)) {

                // Make sure only public members are considered
                static if (__traits(compiles, __traits(getMember, T, element))) {

                    // They also need to have the @Expose attribute
                    static if (hasUDA!(__traits(getMember, T, element), Expose)) {

                        // And the the right index.
                        if (element == index) {

                            // Finally return it.
                            mixin(q{g_push!(typeof(__traits(getMember, T, element)))(state, tPtr.%s);}.format(
                                    element));
                            return 1;
                        }
                    }
                }
            }
        }

        // return other things users might've set.
        lua_pushstring(state, toStringz(index));
        lua_rawget(state, 1);
        return 1;
    };

    static LuaStateFunction __newindex = (state) {

        // Get value
        Variant val = stackToVariant(state);

        // ! remember to pop first
        lua_pop(state, 1);

        // get index.
        string index = stackToVariant(state).coerce!string;

        if (index != "selfPtr") {

            // Push string of self pointer.
            lua_pushstring(state, toStringz("selfPtr"));
            lua_rawget(state, 1);

            T* tPtr = (cast(T*) lua_touserdata(state, -1));
            lua_pop(state, 1);

            // Trait dark magic hide your children.
            static foreach (element; __traits(derivedMembers, T)) {

                // Make sure only public members are considered
                static if (__traits(compiles, __traits(getMember, T, element))) {

                    // They also need to have the @Expose attribute
                    static if (hasUDA!(__traits(getMember, T, element), Expose)) {

                        // And the the right index.
                        if (element == index) {

                            // Finally change it.
                            mixin(q{tPtr.%s = val.coerce!%s;}.format(element,
                                    typeof(__traits(getMember, T, element)).stringof));
                            return 0;
                        }
                    }
                }
            }
        }

        // WE DON'T WANT THE USER TO CHANGE THE SELFPTR.
        return 0;
    };

    LuaTable bindToLua(LuaState state) {

        LuaTable tableRef = state.newTable(T.stringof);
        tableRef.set!LuaStateFunction("new", __new);
        LuaTable table = state.newTable(T.stringof ~ "__callMeta");
        table.set!LuaStateFunction("__call", __new);
        table.metatableTo(tableRef);

        return tableRef;
    }
}

int paramCount(T, string element)() {
    return Parameters!(typeof(__traits(getMember, T, element))).length;
}

string[] params(T, string element)() {
    string[] o = new string[paramCount!(T, element)()];
    foreach (i, param; Parameters!(typeof(__traits(getMember, T, element)))) {
        o[i] = param.stringof;
    }
    return o;
}

string generateDataSetters(string[] params)() {
    string o = q{
        Variant[] params;
        immutable(int) stack = lua_gettop(state);
        foreach (i; 0 .. stack) {
            params ~= stackToVariant(state);
            lua_pop(state, stack);
        }
    };
    static foreach (i, param; params) {
        o ~= q{
            %s _var_%s = params[%s].coerce!%s;
        }.format(param, i, i, param);
    }
    return o;
}

string generateFunctionParams(int count)() {
    string o = "";
    static foreach (i; 0 .. count) {
        static if (i <= count - 2) {
            o ~= q{_var_%s, }.format(i);
        } else {
            o ~= q{_var_%s}.format(i);
        }
    }
    return o;
}

string generateFunction(T, string element)() {
    static if (params!(T, element).length == 0) {
        return q{
            static LuaStateFunction __lua_%s_call_%s = (state) {
                import std.stdio;
                import std.variant;
                import lua.backend;
                lua_pushstring(state, toStringz("selfPtr"));
                lua_rawget(state, 0);

                T* tPtr = (cast(T*) lua_touserdata(state, -1));
                tPtr.%s();

                return 0;
            };
        }.format(T.stringof, element, element);

    } else {
        return q{
            static LuaStateFunction __lua_%s_call_%s = (state) {
                import std.stdio;
                import std.variant;
                import lua.backend;

                // Get data.
                %s

                // Get selfPtr
                lua_pushstring(state, toStringz("selfPtr"));
                lua_rawget(state, 0);

                T* tPtr = (cast(T*) lua_touserdata(state, -1));
                lua_pop(state, 1);


                static if (is(ReturnType!(T.%s) == void)) {
                    // Call function
                    tPtr.%s(%s);

                    return lua_gettop(state);
                } else {
                    g_push!(ReturnType!(T.%s))(state, tPtr.%s(%s));
                    return lua_gettop(state);
                }
            };
        }.format(// first pair  
                T.stringof, element,// get data
                generateDataSetters!(params!(T,
                element)), element,// can't return
                element, generateFunctionParams!(paramCount!(T, element)),

                // can return 
                element, element, generateFunctionParams!(paramCount!(T, element)));
    }
}

mixin template luaImplFuncs(T) {

    // Trait dark magic hide your children.
    static foreach (element; __traits(derivedMembers, T)) {

        // Make sure only public members are considered
        static if (__traits(compiles, __traits(getMember, T, element))) {

            // Make sure it's an exposed function.
            static if (hasUDA!(__traits(getMember, T, element), ExposeFunction)) {

                pragma(msg, "luaBinding: __lua_" ~ T.stringof ~ "_call_" ~ element);
                pragma(msg, "binding: " ~ generateFunction!(T, element));

                mixin(generateFunction!(T, element));

            }

        }

    }

}

/// Binding to D data.
class ManagedUserData(T) {
private:
    LuaState state;
    LuaTable tableRef;

    mixin luaImpl!T;

    this()(LuaState state) {
        // TODO: Do binding via template magic.
        state = state;

        tableRef = bindToLua(state);
    }

    LuaTable newTable(string name, Variant[] args) {
        return new LuaTable(state, "a");
    }
}

class LuaState {
private:
    lua_State* state;
    LuaRegistry registry;
    LuaThread[] threads;

    this(lua_State* state, bool wrapper = false) {
        this.state = state;
        if (!wrapper)
            registry = new LuaRegistry(this);
    }

public:
     ~this() {
        destroy(threads);
        destroy(registry);
        lua_close(state);
    }

    /// Creates a binding to some user data (via pointer)
    ManagedUserData!T bindUserData(T)() {
        return new ManagedUserData!T(this);
    }

    /**
        Creates a new table.
    */
    LuaTable newTable(string name) {
        return new LuaTable(this, name);
    }

    /**
        Creates a new table, which doesn't exist globally.
        Values can only get set while the table is active.
        Table becomes inactive as soon as other data is managed.
    */
    LuaLocalTable newLocalTable() {
        return new LuaLocalTable(this);
    }

    /**
        Creates a new callstack (called threads in lua)

        This can be used cross-threads, be sure to use mutex when needed.
    */
    LuaThread newThread() {
        LuaThread thread = new LuaThread(this);
        threads ~= thread;
        return thread;
    }

    /**
        Execute a string.
    */
    void executeString(string code, string name = "unnamed", bool coroutine = false) {
        if (coroutine) {
            LuaThread t = newThread();
            t.executeString(code);
            return;
        }
        if (luaL_dostring(state, toStringz(code)) != LUA_OK) {
            throw new LuaException(lua_tostring(state, -1).text, name);
        }
    }

    /**
        Execute a file.
    */
    void executeFile(string path, bool coroutine = false) {
        import std.file;

        string data = path.readText;
        executeString(data, path, coroutine);
    }

    ref LuaRegistry getRegistry() {
        return registry;
    }
}
