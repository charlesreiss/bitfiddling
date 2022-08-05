import std.regex;

class LexingError : Exception {
    this(R...)(R msg) {
        import std.conv : text;
        super(text(msg));
    }
}

// Single-state for now...
class Lexer(R=const(char)[], String=string) {
    struct State {
        int index;
        int line;
        int lastLineBreak;
        void updateFrom(R match) {
            import std.traits : Unqual;
            Unqual!(typeof(match[0])) old = ' ';
            foreach(c; match) {
                if (c == '\n' || c == '\r') {
                    if (c == '\r' || old != '\r') line += 1; // count Windows lines too
                    lastLineBreak = index;
                }
                old = c;
                index += 1;
            }
        }
        void reset() { index=0; line=0; lastLineBreak=0; }
        string toString() const {
            import std.conv : text;
            return text(`line `,line,` col `,(index-lastLineBreak));
        }
    }
    struct Lexeme {
        String name;
        R value;
        bool opCast(T:bool)() const nothrow @safe { return this != Lexeme.init; }
    }
    
    R buffer;
    String[] re;
    String[] names;
    R function(in Captures!R)[] wrappers;
    State state;
    
    void reset(R buffer, State state=State.init) {
        this.buffer = buffer;
        this.state = state;
    }
    State save() { return this.state; }
    Lexeme next() {
        Captures!R got = matchFirst(buffer, re);
        if (got.pre.length > 0)
            throw new LexingError("Unexpected text `",got.pre,"' at ",state);
        int idx = got.whichPattern - 1;
        if (idx < 0) return Lexeme.init;
        state.updateFrom(got.hit);
        auto ans = Lexeme(
            names[idx], 
            wrappers[idx] is null ? got.hit : wrappers[idx](got)
        );
        buffer = got.post;
        return ans;
    }
    
    int opApply(scope int delegate(ref Lexeme) dg) {
        int result = 0;
        for(auto l = next(); l; l = next()) {
            result = dg(l);
            if (result) break;
        }
        return result;
    }
    
    Lexeme pattern(String re, String name, R function(in Captures!R) wrapper=null) {
        this.re ~= re;
        this.names ~= name;
        this.wrappers ~= wrapper;
        return Lexeme(name, null);
    }
}

private alias Lexeme = Lexer!().Lexeme;

struct Symbol {
    union {
        string nterm;
        Lexeme token;
    }
    bool isTerm;
    this(string nterm) { this.nterm = nterm; isTerm = false; }
    this(Lexeme token) { this.token = token; isTerm = true; }
    void opAssign(T)(T val) if(is(T:string)) { this.nterm = val; isTerm = false; }
    void opAssign(T)(T val) if(is(T:Lexeme)) { this.nterm = val; isTerm = true; }
}

struct ASTNode {
    string kind;
    ASTNode[] kids;
    this(dchar c) { kind ~= c; }
    this(string flat) { kind = flat; }
    this(string kind, ASTNode[] kids) { this.kind = kind; this.kids = kids; }
    this(Lexeme token) { this.kind = token.name; this.kids = [ASTNode(token.value.idup)]; }
    
    string toString() const {
        import std.conv : text;
        if(kids.length == 0) return text('"', kind, '"');
        return text(kind, kids);
    }
    string payload() const {
        if(kids.length == 0) return kind;
        return kids[0].kind;
    }
}

class ParsingError : Exception {
    this(R...)(R msg) {
        import std.conv : text;
        super(text(msg));
    }
}

class RejectParse : Exception { this() { super("parse rejected by postprocess(...)"); } }

class Rule {
    static int highestId = 0;
    
    int id;
    string name;
    Symbol[] symbols;
    
    ASTNode function(ASTNode nodes) postprocess;
    
    this(string name, Symbol[] symbols, ASTNode function(ASTNode) postprocess=null) {
        this.name = name;
        this.symbols = symbols;
        this.postprocess = postprocess;
    }
    
    string toString(int cursor) const {
        import std.array : Appender;
        Appender!string ans;
        ans ~= name; ans ~= " →";
        foreach(i, sym; symbols) {
            if(i == cursor) ans ~= " ● ";
            else ans ~= " ";
            if(sym.isTerm) {
                ans ~= '{';
                ans ~= sym.token.name;
                ans ~= '}';
            } else {
                ans ~= sym.nterm;
            }
        }
        if(cursor == symbols.length) ans ~= " ●";
        return ans.data;
    }
    override string toString() const { return toString(-1); }
}

private class State {
    Rule rule;
    int dot, reference;
    ASTNode data;
    State[]* wantedBy; // TO DO: should be a collection class instead, but SList!State does not work because it is not reference semantics until after it has elements
    State left, right;
    
    bool isComplete() { return dot == rule.symbols.length; }
    
    this(Rule rule, int dot, int reference, State[]* wantedBy) {
        this.rule = rule;
        this.dot = dot;
        this.reference = reference;
        this.data = ASTNode(rule.name, []);
        this.wantedBy = wantedBy;
    }
    this(Lexeme token, int reference) {
        this.reference = reference;
        this.data = ASTNode(token);
    }
    
    override string toString() const {
        import std.conv : text;
        return text('{', rule.toString(dot), `}, from: `, reference);
    }
    
    State nextState(State child) {
        auto state = new State(rule, dot+1, reference, wantedBy);
        state.left = this;
        state.right = child;
        if(state.isComplete) state.data.kids = state.build;
        return state;
    }
    State nextState(Lexeme token, int reference) {
        return nextState(new State(token, reference));
    }
    ASTNode[] build() {
        import std.array : Appender;
        import std.algorithm : reverse;
        Appender!(ASTNode[]) children;
        State node = this;
        do {
            children ~= node.right.data;
            node = node.left;
        } while (node.left !is null);
        auto c2 = children.data;
        c2.reverse;
        return c2;
    }
    
    void finish() {
        if(rule.postprocess !is null)
            data = rule.postprocess(data);
    }
}


private class Column {
    Grammar grammar;
    int index;
    State[] states;
    State[][string] wants;
    State[] scannable;
    State[][string] completed;

    override string toString() const {
        import std.conv : text;
        return text("\nColumn ",states,"\n    wants", wants);
    }
    
    this(Grammar grammar, int index) {
        this.grammar = grammar;
        this.index = index;
    }
    
    void process() {
        for(auto w=0; w<states.length; w+=1) { // not foreach: can ~= in loop
            auto state = states[w];
            if(state.isComplete) {
                try {
                    state.finish;
                    
                    foreach(left; *(state.wantedBy)) complete(left, state);
                    
                    if(state.reference == index) { // nullables
                        string exp = state.rule.name;
                        completed[exp] ~= state;
                    }
                    
                } catch(RejectParse ex) {}
            } else {
                auto _exp = state.rule.symbols[state.dot];
                if(_exp.isTerm)
                    scannable ~= state;
                else {
                    string exp = _exp.nterm;
                    if(exp in wants) {
                        wants[exp] ~= state;
                        foreach(right; completed.get(exp,[]))
                            complete(state, right);
                    } else { // needed to avoid infinite repeat states...
                        wants[exp] ~= state;
                        predict(exp);
                    }
                }
            }
        }
    }
    
    void predict(string exp) {
        foreach(r; grammar.byName.get(exp,[]))
            states ~= new State(r, 0, index, &wants[exp]);
    }
    
    void complete(State left, State right) {
        states ~= left.nextState(right);
    }
}

class Grammar {
    Rule[] rules;
    string start;
    Rule[][string] byName;
    
    this(Rule[] rules, string start=null) {
        this.rules = rules;
        this.start = (start is null) ? rules[0].name : start;
        foreach(rule; rules) {
            byName[rule.name] ~= rule;
        }
    }
}

class Parser {
    Grammar grammar;
    Lexer!() lexer;
    Column[] table;
    int current;
    Lexer!().State lexerState;
    ASTNode[] results;
    
    this(Grammar grammar, Lexer!() lexer) {
        this.grammar = grammar;
        this.lexer = lexer;
        reset();
    }
    
    Parser reset() {
        lexerState.reset();
        table = [new Column(grammar, 0)];
        table[0].wants[grammar.start] = [];
        table[0].predict(grammar.start);
        // FIXME: start state must not be nullable
        table[0].process;
        current = 0;
        results = null;
        return this;
    }
    
    Parser feed(string chunk) {
        lexer.reset(chunk, lexerState);
        foreach(token; lexer) {
            auto column = table[current];
            if(current > 0) table[current-1] = null; // gc
            auto n = current + 1;
            auto nextColumn = new Column(grammar, n);
            table ~= nextColumn;
            
            foreach(state; column.scannable) {
                auto expect = state.rule.symbols[state.dot];
                if(expect.isTerm && expect.token.name == token.name
                && (expect.token.value.length == 0
                    || expect.token.value == token.value)
                )   nextColumn.states ~= state.nextState(token, current);
            }
            
            nextColumn.process;
            
            if (nextColumn.states.length == 0)
                throw new ParsingError("Unexpected token `",token.value,"' at or before ",lexer.save,/+'\n',column.states+/);

            current += 1;
        }
        results = finish;
        lexerState = lexer.save;
        return this;
    }
    
    ASTNode[] finish(int i=-1) {
        ASTNode[] ans;
        foreach(t; this.table[i<0 ? $-1: i].states) {
            if(t.rule.name == grammar.start
            && t.isComplete
            && t.reference == 0)
                ans ~= t.data;
        }
        return ans;
    }
}
