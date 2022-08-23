import vibe.data.json;
import vibe.core.file;
import vibe.core.log;
import vibe.core.sync;
import std.conv : text;

private {
    /// logStr(3, "yes", "no", "ok") == {"yes":{"no":{"ok":3}}}
    Json logStr(T)(T value, string[] key...) {
        Json ans = serializeToJson(value);
        foreach_reverse(k; key) ans = Json([k:ans]);
        return ans;
    }
    /// reverses logStr
    void unlogTo(T)(Json log, ref T dest) {
        static if (__traits(compiles, dest[`foo`])) {
            foreach(k,v; log.get!(Json[string])) {
                if (k == `.date`) continue; // skip timestamps
                if (k !in dest) dest[k] = typeof(dest[k]).init;
                v.unlogTo(dest[k]);
            }
        } else dest = log.get!T;
    }
    void unlogTo(Json log, ref Json dest) {
        dest = log;
    }
}

/// primitive or string values in associative array with string keys, at any depth
template persistableType(T) {
    static if (is(T:long) || is(T:real) || is(T:string) || is(T:Json))
        enum bool persistableType = true;
    else static if (__traits(isAssociativeArray, T) && is(string : typeof(T.init.keys[0]))) 
        enum bool persistableType = persistableType!(typeof(T.init[``]));
    else
        enum bool persistableType = false;
}


/**
 * A file-based in-memory primitive[string][string]...[string]
 * Works across threads, but not across processes.
 * 
 * By default, the order of concurrent events may be serialized in a different
 * order by the memory and disk copies. This can be overridden by setting the
 * verySafe template argument to true: `Persistent!(string[string][string], true)`
 * 
 * Users should manually synchronize reads, as e.g.
 * 
 * ````d
 * synchronized(pa.mutex.reader) {
 *    foreach(k,v; pa[`foo`]) { writeln(k,": ",v); }
 * }
 * `````
 */
struct Persistent(T, bool verySafe=false) if (persistableType!T) {
    __gshared T data;
    shared TaskReadWriteMutex mutex;
    const string logFile;
    
    this(string filename) {
        this.logFile = filename;
        mutex = cast(shared)new TaskReadWriteMutex(TaskReadWriteMutex.Policy.PREFER_WRITERS);
        if (existsFile(logFile)) {
            auto f = readFileUTF8(logFile);
            synchronized(mutex.writer) {
                try {
                    while(f.length > 1) {
                        f.parseJson.unlogTo(data);
                    }
                } catch(JSONException ex) {
                    logError("Log format wrong " ~ text(ex));
                }
            }
        }
    }
    
    void set(R)(R value, string[] key...) {
        import std.datetime : Clock;
        auto log = logStr(value, key);
        log[`.date`] = Clock.currTime.toISOExtString;
        auto logStr = serializeToJsonString(log) ~ '\n';
        synchronized(mutex.writer) {
            log.unlogTo(data); // somewhat inefficient, but simple
            static if(verySafe) appendToFile(logFile, logStr);
        }
        static if(!verySafe) appendToFile(logFile, logStr);
    }
    
}
