/// copied from strquote.d
void put_json(T)(ref T sb, string s) pure nothrow if (__traits(compiles, sb.put(`3`))) {
    sb.put('"');
    foreach(c; s) 
        switch(c) {
            case '"': sb.put(`\"`); break;
            case '\t': sb.put(`\t`); break;
            case '\\': sb.put(`\\`); break;
            case '\n': sb.put(`\n`); break;
            case '\r': sb.put(`\r`); break;
            case '\b': sb.put(`\b`); break;
            case '\v': sb.put(`\v`); break;
            case '\f': sb.put(`\f`); break;
            default: 
                if(c < 0x20 || c == 0x7F) {
                    sb.put(`\u00`);
                    if ((c&0xf0) < 0xa0) sb.put(cast(char)('0' + (c>>4)));
                    else sb.put(cast(char)('A'-10+(c>>4)));
                    if ((c&0xf) < 0xa) sb.put(cast(char)('0' + (c&0xf)));
                    else sb.put(cast(char)('A'-10+(c&0xf)));
                } else
                    sb.put(c);
        }
    sb.put('"');
}
void put_json(T)(ref T sb, int s) pure nothrow if (__traits(compiles, sb.put('3'))) {
    if (s < 0) {
        sb.put('-');
        s *= -1;
    }
    long top = 1;
    while(top*10 <= s) top *= 10;
    for(; top >= 1; top/=10) {
        sb.put(cast(char)('0' + ((s/top)%10)));
    }
}
void put_json(T,R)(ref T sb, R[string] s) pure if (__traits(compiles, sb.put_json(R.init))) {
    sb.put(`{`);
    bool first = true;
    foreach(k,v; s) {
        if(!first) sb.put(',');
        else first=false;
        sb.put_json(k);
        sb.put(':');
        sb.put_json(v);
    }
    sb.put('}');
}
version(none) // string fits this template too...
void put_json(T,R)(ref T sb, R[] s) pure nothrow if (__traits(compiles, sb.put_json(R.init))) {
    sb.put(`[`);
    bool first = true;
    foreach(k,v; s) {
        if(!first) sb.put(',');
        else first=false;
        sb.put_json(v);
    }
    sb.put(']');
}

string escape_json(T)(T s) {
    import std.array : Appender;
    Appender!string sb;
    sb.put_json(s);
    return sb.data;
}


private{
    struct oneHot {
        int next=1;
        uint length=32;
        bool empty() const { return next==0; }
        int front() const { return next; }
        void popFront() { next <<= 1; length -= 1; }
        int opIndex(int i) const { return next+i; }
    }
    struct twoHot {
        int top=2;
        int bot=1;
        uint length = 32*31/2;
        bool empty() const { return top==0; }
        int front() const { return top|bot; }
        void popFront() { bot<<=1; if (bot == top) { top <<= 1; bot = 1; } length -= 1; }
    }

    int[n] _starter(int n)() {
        int[n] set;
        foreach(i; 0..n) set[i] = 1<<i;
        return set;
    }
    uint _choose_32(int n) {
        uint ans = 1;
        foreach(i; 0..n) {
            ans *= 32-i;
            ans /= (i+1);
        }
        return ans;
    }

    struct nHot(int n) if (n<int.sizeof*4) {
        int[n] set = _starter!n;
        uint length = _choose_32(n);
        bool empty() const { return set[$-1] == 0; }
        int front() const {
            int ans = 0;
            foreach(i; 0..n) ans |= set[i];
            return ans;
        }
        void popFront() {
            foreach(i; 0..n) {
                set[i] <<= 1;
                if (i+1<n && set[i] == set[i+1]) set[i] = 1<<i;
                else break;
            }
            length -= 1;
        }
        // opIndex?
    }

    struct reps(int wid) if (wid<int.sizeof*4) {
        int next = 1;
        uint length = (1<<(wid-1))-1;
        bool empty() const { return next >= 1<<(wid-1); }
        int front() const {
            int ans = next;
            foreach(i; 0..(int.sizeof*8/wid)) ans |= next << (1+i)*wid;
            return ans;
        }
        void popFront() { next += 1; length -= 1; }
    }

    // zero, and then the first few multiples of 32-bit binary phi
    struct zero {
        int next = 0;
        uint length = 9;
        bool empty() const { return next > 0x61c88647; }
        int front() const { return next; }
        void popFront() { next += 0x61c88647; length -=1 ; }
    }
    
    struct onlyzero {
        int next = 0;
        uint length = 1;
        bool empty() const { return next > 0; }
        int front() const { return 0; }
        void popFront() { next += 1; length -=1 ; }
    }

    struct sampler(R...) {
        R gen;
        bool flip = false;
        bool empty() const { return gen[$-1].empty; }
        int front() const {
            int ans = 0;
            foreach(i,ref x; gen) if (!x.empty) { ans = x.front; break; }
            if (flip) ans ^= -1;
            return ans;
        }
        void popFront() {
            if(!flip) flip = true;
            else {
                flip = false;
                foreach(i,ref x; gen) if (!x.empty) { x.popFront; break; }
            }
        }
        uint length() const {
            uint ans = 0;
            foreach(ref x; gen) ans += x.length;
            return ans*2 - flip;
        }
    }
}
/// About 11,000 test cases, very likely to find an error if there is one
alias TestCaseGenerator = sampler!(zero, oneHot, reps!2, twoHot, nHot!3, reps!5, reps!9);

/// About 150 test cases, suitable for multi-input testing
alias SmallTestCaseGenerator = sampler!(zero, oneHot, reps!6);

alias EmptyGenerator = sampler!(onlyzero);

/// All combinations of several generators
struct AllPerm(R...) {
    R gen;
    ulong _length = ulong.max;
    bool empty() const { return gen[$-1].empty; }
    int[R.length] front() const {
        int[R.length] ans;
        static foreach(i; 0..R.length) ans[i] = gen[i].front;
        return ans;
    }
    void popFront() {
        foreach(i,ref x; gen) {
            x.popFront;
            if (x.empty && i+1 < gen.length) x = R[i].init;
            else break;
        }
        _length -= 1;
    }
    ulong length() {
        if (_length < ulong.max) return _length;
        _length = 1;
        static foreach(i; 0..R.length) _length *= R[i].init.length;
        return _length;
    }
}

/// An explicit list of values, re-initializable for AllPerm generation
struct CTSet(Values...) {
    alias T = typeof(Values[0]);
    int i = 0;
    T[Values.length] data = [Values];
    bool empty() const { return i >= data.length; }
    T front() const { return data[i]; }
    void popFront() { i += 1; }
    T length() const { return cast(int)data.length - i; }
}

/// Iterates the given XGen for x, and all combinations of 0 <= y < z <= 32
struct TwoIndex(XGen) {
    XGen gen;
    int y=0, z=1;
    bool empty() const { return gen.empty && y == 31; }
    int[3] front() const {
        int[3] ans;
        ans[0] = gen.front;
        ans[1] = y;
        ans[2] = z;
        return ans;
    }
    void popFront() { 
        if (y == 31) {
            gen.popFront;
            y = 0;
            z = 1;
        } else if (z == 32) {
            y += 1;
            z = y+1;
        } else {
            z += 1;
        }
    }
    ulong length() const {
        return gen.length * 4096;
    }
}



/**
 * A bitwise arithmetic puzzle.
 * 
 * !n:          the number of inputs to the puzzle.
 */
class Task(int n) {
    import std.range.interfaces : InputRange;
    string description;
    int[string] limits;
    string[n] provided;
    bool delegate(int[string]) checker;
    InputRange!(int[n]) cases;
    
    /**
     * description: a string to show the user.
     * provided:    a list of n strings, the names of the puzzle inputs
     * checker:     a predicate, int[string] -> bool, for verifying the final state is correct
     * cases:       a forward range of int[n], the inputs to test
     */
    this(string desc, int[string] limits, string[n] prov, typeof(checker) chk, typeof(cases) cs) {
        import std.range : chain;
        this.description = desc;
        this.limits = limits;
        this.provided = prov;
        this.checker = chk;
        this.cases = cs;
    }
    
    /**
     * A constructor that allows a compile-time provision of n integer generators
     * (to be used with AllPerms)
     */
    static Task make(T...)(string d, int[string] limits, string[n] prov, typeof(checker) chk) {
        import std.range.interfaces : inputRangeObject;
        AllPerm!T gen;
        return new Task(d, limits, prov, chk, inputRangeObject(gen));
    }
    
    static if (n==3) {
        /**
         * A specialized constructor for TwoIndex
         */
        static Task make2Idx(string d, int[string] limits, string[n] prov, typeof(checker) chk) {
            import std.range.interfaces : inputRangeObject;
            TwoIndex!SmallTestCaseGenerator gen;
            return new Task(d, limits, prov, chk, inputRangeObject(gen));
        }
    }
    
    /**
     * Variation on check with program-accessible info
     * 
     * return value: false if there was an error
     * message: textual summary for the user
     * stats: op counts 
     * vars: failing case if not successful (score == 0), unmodified otherwise
     * score: 0 if failed a case, 25 if passed with illegal ops, 50 if passed with legal ops, 100 if passed with few enough legal ops
     * 
     *  25: passed 
     *  50: only allowed ops and small enough constants
     */
    bool check(string code, out string message, out int[string] stats, out int[string] vars, out int score) {
        static import doops, lexparse;
        import std.conv : text;
        try {
            auto c = doops.BitCode(code, provided);
            stats = c.statistics.dup;
            int[string] env;
            int passed = 0;
            foreach(vals; cases) {
                passed += 1;
                env.clear;
                static foreach(i; 0..n) env[provided[i]] = vals[i];
                try {
                    c.compiled(env);
                } catch (doops.ExpressionRuntimeError ex) {
                    score = 0;
                    vars = env.dup;
                    message = text("Test case #", passed, ":<br>", ex.msg);
                    return true;
                } catch (Throwable ex) {
                    score = 0;
                    vars = env.dup;
                    message = text("Test case #", passed, " attempted the impossible and crashed");
                    return true;
                }
                try {
                    if (!checker(env)) {
                        score = 0;
                        vars = env.dup;
                        message = text("Failed test case #", passed);
                        return true;
                    }
                } catch (Throwable ex) {
                    score = 0;
                    vars = env.dup;
                    message = "Error trying to check your answer; did you set all requested variables?";
                    return true;
                }
            }
            score = 50;
            message = "Passed all test cases";
            foreach(k,v; stats)
                if (k == `const`) {
                    if (k in limits && limits[k] < v) { score -= 25; break; }
                } else if (k == `ops`) {
                } else {
                    if (k !in limits || (limits[k] >= 0 && limits[k] < v)) { score -= 25; break; }
                }
            if (score == 50) {
                int tooMany = stats[`ops`] - limits.get(`ops`, int.max);
                if (tooMany <= 0) tooMany = -1;
                score += 400 / (9+tooMany); // -1 = +50, 1 = +40, 2 = +36, 3 = +33, ...
            }
            return true;
        } catch (lexparse.LexingError ex) {
            message = ex.msg;
            return false;
        } catch (lexparse.ParsingError ex) {
            message = ex.msg;
            return false;
        } catch (doops.BadExpression ex) {
            message = ex.msg;
            return false;
        }
    }
}


Task!1[string] one;
Task!2[string] two;
Task!3[string] three;

static this() {
    one[`thirdbits`] = Task!1.make!(EmptyGenerator)( // FIXME: needs zero
        "set `x` to the constant 0x49249249 (which has every third bit set to 1)",
        [`ops`:12,`const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`__ignored__`], (int[string] e) => (e.get(`x`, 0xdeadbeef) == 0x49249249),
    );
    one[`bang`] = Task!1.make!(TestCaseGenerator)(
        "set `y` to 1 if `x` is zero and set `y` to 0 otherwise. (This is what `y = !x` would compute in C, but `!` is not a permitted operator.)",
        [`ops`:12,`const`:5,
        `!`:0,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e) {
            if (e[`x`] != 0) {
                return e.get(`y`, 0xdeadbeef) == 0;
            } else {
                return e.get(`y`, 0xdeadbeef) == 1;
            }
        }
    );
    two[`subtract`] = Task!2.make!(SmallTestCaseGenerator,SmallTestCaseGenerator)(
        "set `z` to `x - y` without using `-` or multi-bit constants.",
        [`ops`:10, `const`:1,
        `!`:-1,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`, `y`], (int[string] e) => (e.get(`z`,0xdeadbeef) == (e[`x`] - e[`y`]))
    );
    two[`isequal`] = Task!2.make!(SmallTestCaseGenerator,SmallTestCaseGenerator)(
        "set `z` to `1` if `x == y`; otherwise set `z` to `0` without using == or multi-bit constants.",
        [`ops`:5, `const`:1,
        `!`:-1,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`, `y`], (int[string] e) {
            if (e[`x`] == e[`y`]) {
                return e.get(`z`, 0xdeadbeef) == 1;
            } else {
                return e.get(`z`, 0xdeadbeef) == 0;
            }
        }
    );
    two[`islessorequal`] = Task!2.make!(SmallTestCaseGenerator,SmallTestCaseGenerator)(
        "set `z` to `1` if `x <= y`; otherwise set `z` to `0`.",
        [`ops`:24, `const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`, `y`], (int[string] e) {
            if (e[`x`] <= e[`y`]) {
                return e.get(`z`, 0xdeadbeef) == 1;
            } else {
                return e.get(`z`, 0xdeadbeef) == 0;
            }
        }
    );
    one[`bottom`] = Task!1.make!(CTSet!(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32))(
        "set the low-order `b` bits of `x` to 1; the others to 0. For example, if `b` is 3, `x` should be 7. Pay special attention to the edge cases: if `b` is 32 `x` should be &minus;1; if `b` is 0 `x` should be 0. Do not use `-` in your solution.",
        [`ops`:40,
        `!`:-1,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`b`], (int[string] e){
            int x = e[`b`];
            int ans = 0;
            foreach(i; 0..x) { ans <<= 1; ans |= 1; }
            return e.get(`x`,0xdeadbeef) == ans;
        }
    );
    one[`anybit`] = Task!1.make!TestCaseGenerator(
        "set `y` to `1` if any bit in `x` is `1`; otherwise set `y` to `0`.", 
        [`ops`:40,
        `!`:0,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e) => (e.get(`y`,0xdeadbeef) == !!e[`x`])
    );
    one[`fiveeighths`] = Task!1.make!(TestCaseGenerator)(
        "set `y` to be 5/8 of `x` (rounded toward zero). This should work for both positive and negative numbers, even if neither `5*x` nor `x/8` can be properly represented in 32 bits, but does not need to work for 0x80000000.",
        [//`ops`:20,
        `!`:-1,`~`:-1, `+`:-1,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e) => (e[`x`] == int.min || e.get(`y`,0xdeadbeef) == (5*cast(long)e[`x`])/8)
    );
    one[`bitcount`] = Task!1.make!TestCaseGenerator(
        "set `y` to the number of bits in `x` that are `1`.",
        [`ops`:40,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e){
            int x = e[`x`];
            int ans = 0;
            foreach(i; 0..32) ans += (x>>i)&1;
            return e.get(`y`,0xdeadbeef) == ans;
        }
    );
    three[`getbits`] = Task!3.make2Idx(
        "select bits `y` through `z-1` of `x` and return them in the low-order bits of `w`. For example, `getbits(0b1110_1100_1010,3,7)` would return 0b1001 = 9. You may assume 0 ≤ y < z ≤ 32. You'll probably want to include a solution to the \"bottom\" task in solving this task.",
        ["ops":15,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`,`y`,`z`], (int[string] e){
            int ans = e[`x`] >> e[`y`];
            if(e[`z`]-e[`y`] < 32) ans &= (1<<(e[`z`]-e[`y`]))-1;
            return e.get(`w`,0xdeadbeef) == ans;
        }
    );
    one[`endian`] = Task!1.make!TestCaseGenerator(
        "set `y` to an endian-swapped version of `x`",
        [`ops`:15, `const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e){
            int x = e[`x`];
            int z = ((x&0xFF)<<24) | (((x>>8)&0xFF)<<16) | (((x>>16)&0xFF)<<8) | ((x>>24)&0xFF);
            return e.get(`y`,0xdeadbeef) == z;
        }
    );
    one[`reverse`] = Task!1.make!TestCaseGenerator(
        "set `y` to a bit-reversed version of `x`.",
        [`ops`:40,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e){
            int x = e[`x`];
            int z = 0;
            foreach(i; 0..32) z |= ((x>>i)&1)<<(31-i);
            return e.get(`y`,0xdeadbeef) == z;
        }
    );
    one[`allevenbits`] = Task!1.make!TestCaseGenerator(
        "set `y` to `1` if all the even-numbered bits of `x` are set to 1 (where bit 0 is the least significant bit); otherwise set `y` to `0`",
        [`ops`:12,`const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e){
            int x = e[`x`];
            if ((x & 0x55555555) == 0x55555555) {
                return e.get(`y`,0xdeadbeef) == 1;
            } else {
                return e.get(`y`,0xdeadbeef) == 0;
            }
        }
    );
    two[`addok`] = Task!2.make!(SmallTestCaseGenerator,SmallTestCaseGenerator)(
        "set `z` to a true value (like 1) if `x + y` will not overflow; otherwise set `z` to 0.",
        [`ops`:20, `const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1,`*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`, `y`], (int[string] e) {
            long lsum = cast(long)e[`x`] + cast(long)e[`y`];
            if (e[`z`]) {
                return lsum == cast(long)( cast(int)( lsum ) );
            } else {
                return lsum != cast(long)( cast(int)( lsum ) );
            }
        }
    );
    one[`evenbitparity`] = Task!1.make!(TestCaseGenerator)(
        "set `y` to `0` if an even number of the even-indexed bits are 1; otherwise, set `y` to `1`. (Bit 0 of `x` is the 1s place.) For example: for x = 0, y should be 0 (no bits are 1); for x = 2, y should be 0 (all 1 bits are odd-numbered); for x = 3, y should be 1; for x = 5, y should be 0, for x = 21, y should be 1",
        [`ops`:15, `const`:8,
        `!`:-1,`~`:-1, `+`:-1,`-`:-1,`*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`x`], (int[string] e) {
            int result = 0;
            int i = 0;
            int x = e[`x`];
            for (i = 0; i < 32; i += 2) {
                result ^= (x >> i) ^ 0x1;
            }
            return (result & 1) == (e.get(`y`, 0xdeadbeef));
        }
    );
}

version(none)
void main() {
    import std.datetime.stopwatch, std.stdio;
    StopWatch sw;
    sw.start();
    TestCaseGenerator g;
    writeln(`big: `, g.length);
    writeln(`small: `, SmallTestCaseGenerator.init.length);
    int cnt = 0;
    foreach(i; g) { cnt += 1; }
    sw.stop();
    writeln(cnt, " samples in ", sw.peek);
    
    import std.range;
    
    sw.reset();
    sw.start();
    AllPerm!(oneHot, CTSet!(2,3,4), oneHot) ooo;
    writeln(ooo.length);
    cnt = 0;
    foreach(i; ooo) { cnt += 1; }
    sw.stop();
    writeln(cnt, " samples in ", sw.peek);
   
//    auto t = Task!2.make!(oneHot, CTSet!(0,1,3,1234))(
    auto t = Task!2.make!(sampler!oneHot, sampler!(oneHot, twoHot))(
        `set x = a + b without using +`,
        [`ops`:100,
        `!`:-1,`~`:-1, `+`:0,`-`:0, `*`:0,`%`:0,`/`:0, `<<`:-1,`>>`:-1, `&`:-1,`^`:-1,`|`:-1],
        [`a`, `b`],
        (int[string] e) => (e.get(`x`,0xdeadbeef) == e[`a`]+e[`b`]),
    );
    
    string msg = t.check(`A=a; A += b; x = A`);
    writeln(msg);
    
    string m; int[string] use; int s;
    bool ok = t.check(`A=a; A += b; x = A`, m, use, s);
    writeln(ok, m, use, s);
    
    ok = t.check(`
        w = a; y = b;
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        A = w^y
        B = (w&y)<<1
        w = A; y = B
        x = w
    `, m, use, s);
    writeln(ok, m, use, s);
}
