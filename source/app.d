/+
 + Plan:
 +  php checks netbadge, writes user-session.nonce
 +  php opens websocket, sends (login, id, nonce)
 +  
 + server maintains
 +  score board
 +  set of puzzles
 +  log of all submissions
 + 
 + connection maintains
 +  state: puzzle[i] -or- board -or- personal list
 + 
 + js maintains
 +  code editor
 +  error reporting
 +/
module app;

import vibe.core.log;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.web.web;
import vibe.http.websockets : WebSocket, handleWebSockets;
import vibe.data.json;
import vibe.core.file;
import vibe.stream.tls;
static import tasks;
import persaa;

/**
 * scores["mst3k"]["anybit"] = ["+":3, "&":2, "ops":5, "score":100];
 * scores["mst3k"]["bitcount"] = ["+":31, ">>":31, "&":32, "ops":94, "score":50];
 * scores["mst3k"]["mystery"] = ["score":0];
 */
Persistent!(int[string][string][string])* scores;
/**
 * nicknames["lat7h"] = "the Prof"
 */
Persistent!(string[string])* nicknames;
/**
 * lastCode["lat7h"]["anybit"] = "y = !!x"
 */
Persistent!(string[string][string])* lastCode;

import std.regex : ctRegex, replaceAll;
enum ban_characters = ctRegex!"[^-_ 0-9a-zA-Z]";


shared static this() {
    scores = new typeof(*scores)("logs/scores.log");
    nicknames = new typeof(*nicknames)("logs/nicknames.log");
    lastCode = new typeof(*lastCode)("logs/code.log");
}

string lateness(string user, out bool open) {
    import std.datetime;
    import dateparser : parse;
    import std.conv : text;
    try {
        auto config = readFileUTF8(`config.json`).parseJsonString;
        auto openat = config[`open`].get!string.parse;
        auto due = config[`due`].get!string.parse;
        auto close = config[`close`].get!string.parse;
        if (`extensions` in config) {
            foreach(uid,days; config[`extensions`].get!(Json[string])) {
                logInfo("extension %s %s", uid, days);
                if (uid == user) {
                    openat += dur!"days"(days.get!int);
                    due += dur!"days"(days.get!int);
                    close += dur!"days"(days.get!int);
                }
            }
        }
        logInfo("Due: %s", due);
        auto now = Clock.currTime;
        if (now < openat) { open = false; return text(`This assignment will open `, open); }
        if (now > close) { open = false; return text(`This assignment is now closed`); }
        open = true;
        if (now < due) return text(`Open; due: `, due);
        return text(`Past-due; was due `, due, ` and closes `, close);
    } catch(Throwable ex) {
        logInfo("%s", ex);
        open = true;
        return `Due date not configured in system; see course materials for due date`;
    }
}

class WebsocketService {
    // @path("/") void getHome() { render!("index.dt"); }

    @path("/ws") void getWebsocket(scope WebSocket socket){
        void err(string message, string type="error") { 
            if (socket.connected) 
                socket.send(serializeToJsonString(["type":type,"message":message]));
        }
        logInfo("Got new web socket connection.");
        scope(exit) logInfo("Client disconnected.");
        try {
            if (!socket.waitForData) return;
            Json auth = socket.receiveText.parseJsonString;
            auto user = auth[`user`].get!string;
            if (!existsFile(`logs/sessions/`~user)
            || readFileUTF8(`logs/sessions/`~user) != auth[`token`]) { 
                err("session expired", "reauthenticate");
                return; 
            }
            
            bool open = true;
            socket.send(serializeToJsonString([
                "type":Json("welcome"),
                "due":Json(lateness(user, open)),
            ]));
            while(socket.waitForData) {
                auto message = socket.receiveText;
                auto data = message.parseJsonString;
                switch(data["req"].get!string) {
                    case `status`: {
                        
                        Json[string] msg;
                        foreach(n,_; tasks.one) msg[n] = Json(null);
                        foreach(n,_; tasks.two) msg[n] = Json(null);
                        foreach(n,_; tasks.three) msg[n] = Json(null);
                        if(user in scores.data) {
                            synchronized(scores.mutex.reader) {
                                foreach(n,v; scores.data[user]) msg[n] = Json(cast(int)v[`score`]);
                            }
                        }
                        socket.send(serializeToJsonString([
                            "type":Json("you"),
                            "status":Json(msg),
                            "nickname":Json(nicknames.data.get(user, ``).replaceAll(ban_characters, ``)),
                            "order":serializeToJson(tasks.order),
                        ]));
                    } break;
                    case `code`: {
                        auto late_message = lateness(user, open);
                        if (!open) {
                            err(late_message);
                            break;
                        }
                        // fix me: send code to Task, report results
                        string code = data[`code`].get!string;
                        string task = data[`task`].get!string;
                        
                        string msg; int[string] use; int score; bool ok;
                        int[string] limits;
                        try {
                            if (task in tasks.one) {
                                ok = tasks.one[task].check(code, msg, use, score);
                                limits = tasks.one[task].limits;
                            } else if (task in tasks.two) {
                                ok = tasks.two[task].check(code, msg, use, score);
                                limits = tasks.two[task].limits;
                            } else if (task in tasks.three) {
                                ok = tasks.three[task].check(code, msg, use, score);
                                limits = tasks.three[task].limits;
                            }
                            else { ok = false; msg = "Unknown task: "~task; }
                        } catch (Throwable ex) {
                            ok = false;
                            score = 0;
                            msg = "This code exposed a bug in the website; please email it to your professor to be fixed.";
                            logInfo("%s", ex);
                        }
                        //else { ok = false; msg = "Unknown task: "~task; }
                        if (!ok) err(msg);
                        else {
                            use[`score`] = score;
                            scores.set(use, user, task);
                            lastCode.set(code, user, task);
                            socket.send(serializeToJsonString([
                                "type":Json("results"),
                                "message":Json(msg),
                                "limits":serializeToJson(limits),
                                "results":serializeToJson(use),
                            ]));
                        }
                    } break;
                    case `scores`: {
                        // fix me: show detailed scoreboard for all nicknamed people who did that task
                        string task = data[`task`].get!string;
                        int[string][string] board;
                        synchronized(nicknames.mutex.reader) {
                        synchronized(scores.mutex.reader) {
                            foreach(u,name; nicknames.data) if (name.length > 0) {
                                if(u in scores.data && task in scores.data[u]) {
                                    if (scores.data[u][task]["score"] >= 100)
                                        board[name] = scores.data[u][task];
                                }
                            }
                        }
                        }
                        socket.send(serializeToJsonString([
                            "type":Json("board"),
                            "task":Json(task),
                            "board":serializeToJson(board),
                        ]));
                    } break;
                    case `task`: {
                        string task = data[`task`].get!string;
                        string description;
                        int[string] opLimits;
                        string[] provided;
                        if (task in tasks.one) {
                            description = tasks.one[task].description;
                            opLimits = tasks.one[task].limits;
                            provided = tasks.one[task].provided;
                        } else if (task in tasks.two) {
                            description = tasks.two[task].description;
                            opLimits = tasks.two[task].limits;
                            provided = tasks.two[task].provided;
                        } else if (task in tasks.three) {
                            description = tasks.three[task].description;
                            opLimits = tasks.three[task].limits;
                            provided = tasks.three[task].provided;
                        } else { err("Unknown task: "~task); break; }
                        string code = ``;
                        Json lastRun = null;
                        if (user in lastCode.data && task in lastCode.data[user]) {
                            synchronized(lastCode.mutex.reader) {
                                code = lastCode.data[user][task];
                            }
                        }
                        if (user in scores.data && task in scores.data[user]) {
                            synchronized(scores.mutex.reader) {
                                lastRun = serializeToJson(scores.data[user][task]);
                            }
                        }
                        socket.send(serializeToJsonString([
                            "type":Json("task"),
                            "task":Json(task),
                            "provided":serializeToJson(provided),
                            "description":Json(description),
                            "limits":serializeToJson(opLimits),
                            "code":Json(code),
                            "results":lastRun,
                        ]));
                    } break;
                    case `nickname`: {
                        nicknames.set(data[`name`].get!string.replaceAll(ban_characters, ``), user);
                        socket.send(serializeToJsonString([
                            "type":Json("welcome"),
                        ]));
                    } break;
                    default:
                        err("Unknown request:\n"~message);
                }
            }
        } catch(Throwable ex) {
            logInfo("%s", ex);
            err("malformed data; websocket connection closed " ~ ex.toString); 
        }
    }
}


shared static this() {
    import std.algorithm.iteration : map;
    import std.array : array;

    auto settings = new HTTPServerSettings;
    auto config = readFileUTF8(`config.json`).parseJsonString;
    settings.port = config[`port`].get!ushort;
    settings.hostName = config[`host`].get!string;
    settings.bindAddresses = config["ip"].get!(Json[]).map!(a=>a.get!string).array;
    settings.tlsContext = createTLSContext(TLSContextKind.server);
    settings.tlsContext.useCertificateChainFile(config[`certificate chain`].get!string);
    settings.tlsContext.usePrivateKeyFile(config[`private key`].get!string);

    auto router = new URLRouter;
    router.registerWebInterface(new WebsocketService);
    router.get("*", serveStaticFiles("public/"));

    listenHTTP(settings, router);
}
