import lexparse;

private ASTNode discard(ASTNode nodes) { return ASTNode(nodes.kind, null); }
private ASTNode selector(n...)(ASTNode nodes) {
    ASTNode[] kids; foreach(i; n) kids ~= nodes.kids[i];
    return ASTNode(nodes.kind, kids);
}
private ASTNode flatten(int n)(ASTNode nodes) { return nodes.kids[n]; }
private ASTNode listify(int here, int recur)(ASTNode nodes) {
    static if (here < recur) 
        return ASTNode(nodes.kind, [nodes.kids[here]] ~ nodes.kids[recur].kids);
    else
        return ASTNode(nodes.kind, nodes.kids[recur].kids ~ [nodes.kids[here]]);
}
private ASTNode listify(int here, int delim, int recur)(ASTNode nodes) {
    static if (here < recur)
        return ASTNode(nodes.kind, [nodes.kids[here], nodes.kids[delim]] ~ nodes.kids[recur].kids);
    else
        return ASTNode(nodes.kind, nodes.kids[recur].kids ~ [nodes.kids[delim], nodes.kids[here]]);
}

private Parser p;
static this() {
    auto lex = new Lexer!();
    auto white = lex.pattern(`(\s|//[^\n\r]*|/\*.*?\*/)+`, ` `);
    auto hex = lex.pattern(`\b0[xX][0-9a-fA-F]+\b`, `h`);
    auto dec = lex.pattern(`\b[1-9][0-9]*\b`, `d`);
    auto oct = lex.pattern(`\b0[0-7]*\b`, `o`);
    auto lparen = lex.pattern(`\(`, `(`);
    auto rparen = lex.pattern(`\)`, `)`);
    auto unary = lex.pattern(`[!~]`, `u`);
    auto eq = lex.pattern(`<<=|>>=|[-+*/%^|&]?=`, `=`);
    auto add = lex.pattern(`[-+]`, `p`);
    auto mul = lex.pattern(`[*/%]`, `m`);
    auto shift = lex.pattern(`<<|>>`, `s`);
    auto and = lex.pattern(`\&`, `&`);
    auto xor = lex.pattern(`\^`, `^`);
    auto or = lex.pattern(`\|`, `|`);
    auto _int = lex.pattern(`\bint\b`, `int`);
    auto word = lex.pattern(`\b\w+\b`, `word`);
    auto end = lex.pattern(`\s*[,;][\s,;]*`, `;`);
    
    auto gram = new Grammar([
        new Rule(`any`, [Symbol(`gap`), Symbol(`asgn`), Symbol(`gap`)], &selector!(1)),
        new Rule(`any`, [Symbol(`gap`), Symbol(`asgn`), Symbol(`gap`), Symbol(end), Symbol(`gap`)], &selector!(1)),
        new Rule(`any`, [Symbol(`gap`), Symbol(`asgn`), Symbol(`gap`), Symbol(end), Symbol(`any`)], &listify!(1, 4)),
        new Rule(`any`, [Symbol(`gap`), Symbol(`asgn`), Symbol(`any`)], &listify!(1, 2)),
            
        new Rule(`asgn`, [Symbol(word), Symbol(`gap`), Symbol(eq), Symbol(`gap`), Symbol(`math`)], 
            &selector!(0,2,4)),
        new Rule(`asgn`, [Symbol(_int), Symbol(`gap`), Symbol(word), Symbol(`gap`), Symbol(eq), Symbol(`gap`), Symbol(`math`)], 
            &selector!(2,4,6)),
    
        // to do: add in assignment
    
    
        new Rule(`math`, [Symbol(`ex12`)], &flatten!0),
        
        new Rule(`x`, [Symbol(hex)], &flatten!0),
        new Rule(`x`, [Symbol(dec)], &flatten!0),
        new Rule(`x`, [Symbol(oct)], &flatten!0),
        new Rule(`x`, [Symbol(word)], &flatten!0),
        new Rule(`x`, [Symbol(lparen),Symbol(`gap`),Symbol(`math`),Symbol(`gap`),Symbol(rparen)], &flatten!2),
        
        new Rule(`ex6`, [Symbol(unary),Symbol(`gap`),Symbol(`ex6`)], &selector!(0, 2)),
        new Rule(`ex6`, [Symbol(add),Symbol(`gap`),Symbol(`ex6`)], &selector!(0, 2)),
        new Rule(`ex6`, [Symbol(`x`)], &flatten!0),

        new Rule(`ex7`, [Symbol(`ex7`),Symbol(`gap`),Symbol(mul),Symbol(`gap`),Symbol(`ex6`)], &selector!(0, 2, 4)),
        new Rule(`ex7`, [Symbol(`ex6`)], &flatten!0),

        new Rule(`ex8`, [Symbol(`ex8`),Symbol(`gap`),Symbol(add),Symbol(`gap`),Symbol(`ex7`)], &selector!(0, 2, 4)),
        new Rule(`ex8`, [Symbol(`ex7`)], &flatten!0),

        new Rule(`ex9`, [Symbol(`ex9`),Symbol(`gap`),Symbol(shift),Symbol(`gap`),Symbol(`ex8`)], &selector!(0, 2, 4)),
        new Rule(`ex9`, [Symbol(`ex8`)], &flatten!0),

        new Rule(`ex10`, [Symbol(`ex10`),Symbol(`gap`),Symbol(and),Symbol(`gap`),Symbol(`ex9`)], &selector!(0, 2, 4)),
        new Rule(`ex10`, [Symbol(`ex9`)], &flatten!0),

        new Rule(`ex11`, [Symbol(`ex11`),Symbol(`gap`),Symbol(xor),Symbol(`gap`),Symbol(`ex10`)], &selector!(0, 2, 4)),
        new Rule(`ex11`, [Symbol(`ex10`)], &flatten!0),

        new Rule(`ex12`, [Symbol(`ex12`),Symbol(`gap`),Symbol(or),Symbol(`gap`),Symbol(`ex11`)], &selector!(0, 2, 4)),
        new Rule(`ex12`, [Symbol(`ex11`)], &flatten!0),
        
        new Rule(`gap`, [Symbol(white)], &discard),
        new Rule(`gap`, []),
    ]);

    p = new Parser(gram, lex);
}

class BadExpression : Exception {
    this(R...)(R msg) {
        import std.conv : text;
        super(text(msg));
    }
}

bool isIdentifier(string s) {
    import std.uni;
    if (s.length < 0) return false;
    if (!s[0].isAlpha) return false;
    if (s == "auto" || s == "break" || s == "case" || s == "char" || s == "const" || s == "continue" || s == "default" || s == "do" || s == "double" || s == "else" || s == "enum" || s == "extern" || s == "float" || s == "for" || s == "goto" || s == "if" || s == "int" || s == "long" || s == "register" || s == "return" || s == "short" || s == "signed" || s == "sizeof" || s == "static" || s == "struct" || s == "switch" || s == "typedef" || s == "union" || s == "unsigned" || s == "void" || s == "volatile" || s == "while") return false;
    return true;
}


/**
 * Verifies that everything is correctly formatted:
 * no 09 or 34cow or use of undeclared or ...
 * Throws BadExpression exception if something is wrong.
 */
void checkTree(ASTNode t, ref int[string] values, ref int[string] opcount) {
    import std.conv : to;
    static import core.bitop;
    switch(t.kind) {
        case `any`: foreach(kid; t.kids) checkTree(kid, values, opcount); break;
        case `asgn`:
            if (!t.kids[0].payload.isIdentifier) throw new BadExpression('"',t.kids[0].payload,`" is not a legal identifier`);
            auto op = t.kids[1].payload;
            if (op != `=`) {
                checkTree(t.kids[0], values, opcount);
                op = op[0..$-1]; opcount[op] += 1; 
                opcount[`ops`] += 1;
            }
            checkTree(t.kids[2], values, opcount);
            values[t.kids[0].payload] = 0;
            break;
        case `h`:
            int n = cast(int)to!uint(t.payload[2..$], 16);
            int bits = (n==0?0:core.bitop.bsr(n)+1);
            if (bits > opcount.get(`const`,0)) opcount[`const`] = bits;
            break;
        case `o`:
            int n = cast(int)to!uint(t.payload, 8);
            int bits = (n==0?0:core.bitop.bsr(n)+1);
            if (bits > opcount.get(`const`,0)) opcount[`const`] = bits;
            break;
        case `d`:
            int n = cast(int)to!uint(t.payload, 10);
            int bits = (n==0?0:core.bitop.bsr(n)+1);
            if (bits > opcount.get(`const`,0)) opcount[`const`] = bits;
            break;
        case `word`:
            if (t.payload !in values) throw new BadExpression('"',t.payload,`" cannot be used before it has a value`);
            break;
        case `ex6`:
            opcount[t.kids[0].payload] += 1;
            opcount[`ops`] += 1;
            checkTree(t.kids[1], values, opcount);
            break;
        case `ex7`: case `ex8`: case `ex9`: case `ex10`: case `ex11`: case `ex12`:
            checkTree(t.kids[0], values, opcount);
            opcount[t.kids[1].payload] += 1;
            opcount[`ops`] += 1;
            checkTree(t.kids[2], values, opcount);
            break;
        default:
            throw new BadExpression("Something you typed confused our parser\n    Parser state: ", t);
    }
}

/**
 * Verifies that everything is correctly formatted:
 * no 09 or 34cow or use of undeclared or ...
 * Throws BadExpression exception if something is wrong.
 */
int delegate(ref int[string]) toFunc(ASTNode t) {
    import std.conv : to;
    switch(t.kind) {
        case `any`: 
            auto bits = new int delegate(ref int[string])[t.kids.length];
            foreach(i, kid; t.kids) bits[i] = toFunc(kid);
            return (ref int[string] env) {
                foreach(bit; bits) bit(env);
                return 0;
            };
        case `asgn`:
            auto dst = t.kids[0].payload;
            auto rhs = toFunc(t.kids[2]);
            switch(t.kids[1].payload) {
                case `=`: return (ref int[string] env) => env[dst] = rhs(env);
                case `*=`: return (ref int[string] env) => env[dst] *= rhs(env);
                case `/=`: return (ref int[string] env) => env[dst] /= rhs(env);
                case `%=`: return (ref int[string] env) => env[dst] %= rhs(env);
                case `+=`: return (ref int[string] env) => env[dst] += rhs(env);
                case `-=`: return (ref int[string] env) => env[dst] -= rhs(env);
                case `<<=`: return (ref int[string] env) => env[dst] <<= rhs(env);
                case `>>=`: return (ref int[string] env) => env[dst] >>= rhs(env);
                case `&=`: return (ref int[string] env) => env[dst] &= rhs(env);
                case `^=`: return (ref int[string] env) => env[dst] ^= rhs(env);
                case `|=`: return (ref int[string] env) => env[dst] |= rhs(env);
                default: assert(0);
            }

        case `h`:
            int n = cast(int)to!uint(t.payload[2..$], 16);
            return (ref int[string] env) => n;
        case `o`:
            int n = cast(int)to!uint(t.payload, 8);
            return (ref int[string] env) => n;
        case `d`:
            int n = cast(int)to!uint(t.payload, 10);
            return (ref int[string] env) => n;
        case `word`:
            auto n = t.payload;
            return (ref int[string] env) => env[n];

        case `ex6`:
            auto inner = toFunc(t.kids[1]);
            switch(t.kids[0].payload) {
                case `+`: return inner;
                case `-`: return (ref int[string] env) => -inner(env);
                case `~`: return (ref int[string] env) => ~inner(env);
                case `!`: return (ref int[string] env) => cast(int)!inner(env);
                default: assert(0);
            }
        case `ex7`: case `ex8`: case `ex9`: case `ex10`: case `ex11`: case `ex12`:
            auto lhs = toFunc(t.kids[0]);
            auto rhs = toFunc(t.kids[2]);
            switch(t.kids[1].payload) {
                case `*`: return (ref int[string] env) => lhs(env)*rhs(env);
                case `/`: return (ref int[string] env) => lhs(env)/rhs(env);
                case `%`: return (ref int[string] env) => lhs(env)%rhs(env);
                case `+`: return (ref int[string] env) => lhs(env)+rhs(env);
                case `-`: return (ref int[string] env) => lhs(env)-rhs(env);
                case `<<`: return (ref int[string] env) => lhs(env)<<rhs(env);
                case `>>`: return (ref int[string] env) => lhs(env)>>rhs(env);
                case `&`: return (ref int[string] env) => lhs(env)&rhs(env);
                case `^`: return (ref int[string] env) => lhs(env)^rhs(env);
                case `|`: return (ref int[string] env) => lhs(env)|rhs(env);
                default: assert(0);
            }
        default:
            throw new BadExpression("Something you typed confused the parser\n    Parser state: ", t, `
Please report this full error message and the code you typed to cause it
to your professor.`);
    }
}

struct BitCode {
    int[string] statistics;
    int delegate(ref int[string] env) compiled;
    this(string code) {
        p.reset();
        p.feed(code);
        if (p.results.length == 0)
            throw new BadExpression(`Parse failed without encountering any known error.
Please report this full error message and the code you typed to cause it
to your professor.`);
        auto ast = p.results[0]; // unambiguous grammar so [0] is the only one
        int[string] vars;
        statistics = ["~":0,"!":0,"+":0,"-":0,"*":0,"%":0,"/":0,"<<":0,">>":0,"|":0,"^":0,"&":0,"ops":0];
        checkTree(p.results[0], vars, statistics);
        compiled = toFunc(p.results[0]);
    }
    this(T)(string code, T v) {
        p.reset();
        p.feed(code);
        if (p.results.length == 0)
            throw new BadExpression(`Parse failed without encountering any known error.
Please report this full error message and the code you typed to cause it
to your professor.`);
        auto ast = p.results[0]; // unambiguous grammar so [0] is the only one
        int[string] vars;

    debug(write) import std.stdio;
        static if (is(T : string) )
            vars[v] = int.max;
        else static if (__traits(compiles, v.emptyObject))
            try {
                foreach(string k, _; v) { debug(write) writeln(`jaa `, k, v);  vars[cast(string)k] = int.max; }
            } catch {
                foreach(k; v) { debug(write) writeln(`jda `, k, v);  vars[cast(string)k] = int.max; }
            }
        else static if (__traits(compiles, v.byKey))
            foreach(k; v.byKey) { debug(write) writeln(`aa `, k, v);  vars[cast(string)k] = int.max; }
        else static if (__traits(compiles, v.front) || __traits(compiles, v[0]))
            foreach(k; v) { debug(write) writeln(`da `, k, v); vars[cast(string)k] = int.max; }
        else static assert(false);
        
        auto before = vars.dup;
        statistics = ["~":0,"!":0,"+":0,"-":0,"*":0,"%":0,"/":0,"<<":0,">>":0,"|":0,"^":0,"&":0,"ops":0];
        checkTree(p.results[0], vars, statistics);
        foreach(k,v2; before)
            if (vars[k] != v2)
                throw new BadExpression('"',k,`" is an input and must not be modified.`);

        compiled = toFunc(p.results[0]);
    }
}

version(none)
void main() {
    import std.stdio;

    p.reset();
    p.feed(`foob = 3;
baz = 0x23 ^ foo + (0x23 & 3)
baz += 0+(1+2)+-01
ten = 1 + 3 * 3
four = 1 ^ 2 + 3
seven = 1 ^ 2 * 3
two = 8-4>>1
neg2 = 4-8>>1
`);
    if (false && p.results.length > 1) {
        writeln("Found ", p.results.length, " distinct parses");
        foreach(pp; p.results)
            writeln("  ",pp);
    }

    if(p.results.length == 0) {
        writeln("found but failed to parse");
    } else {
        int[string] vars = [`foo`:12345], ops;
        checkTree(p.results[0], vars, ops);
        auto f = toFunc(p.results[0]);
        writeln(p.results[0]);
        writeln(`var `, vars);
        writeln(`ops `, ops);
        writeln(f(vars));
        writeln(`var `, vars);
        
        import std.datetime.stopwatch;
        import tasks;
        TestCaseGenerator g;
        StopWatch sw;
        int cnt = 0;
        sw.start();
        foreach(k; g) {
            vars[`foo`] = k;
            f(vars);
            if (vars[`foo`] & 1) cnt += 1;
        }
        sw.stop();
        writeln(sw.peek(), " ", cnt);
        
        SmallTestCaseGenerator s1,s2;
        cnt = 0;
        sw.reset();
        sw.start();
        foreach(k1; s1) {
            vars[`foo`] = k1;
            foreach(k2; s2) {
                vars[`xyxxy`] = k2;
                f(vars);
                if (vars[`foo`] & 1) cnt += 1;
            }
        }
        sw.stop();
        writeln(sw.peek(), " ", cnt);
        
    }
/+
import vibe.data.json : Json;
auto k0 = [`foo`:0];
auto k1 = Json([`foo`:Json(0)]);
auto k2 = [`foo`];
auto k3 = Json([Json(`foo`)]);

    auto got = BitCode(`foob = 3;
baz = 0x23 ^ foo + (0x23 & 3)
baz += 0+(1+2)+-01
ten = 1 + 3 * 3
four = 1 ^ 2 + 3
seven = 1 ^ 2 * 3
two = 8-4>>1
neg2 = 4-8>>1
`, `foo`);
    writeln(got.statistics);
+/
}

