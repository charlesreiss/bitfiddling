<!DOCTYPE html>
<html><head><title>Bitwise operation practice site</title>
<script src="showdown.js"></script>
<style>
    th,td { align: left; }
    th.taskgroup { background-color: rgba(90%, 90%, 90%, 1.0); }
    body { background-color: white; color: black; }
    body, code, pre, tt, input, textarea { font-size: 12pt; line-height: 1.5em; }
    code { padding: 1px; border: 1px solid rgba(0,0,0,0.125); background: rgba(0,0,0,0.0625);  border-radius:4px; }
    .compile { font-weight: bold; }
</style>
<script>//<!--

var socket;
var md = new showdown.Converter();

<?php /** Authentication: uses netbadge for php but internal tokens for websockets */
$user = $_SERVER['PHP_AUTH_USER'];
echo 'console.log("'.$user.'");'."\n";

if ($user == "lat7h" && $_GET['user']) $user=$_GET['user'];

$token = bin2hex(openssl_random_pseudo_bytes(4)) . " " . date(DATE_ISO8601);
file_put_contents("/opt/coa1-bithw/logs/sessions/$user", "$token");
?>
var user = "<?=$user;?>";
var token = "<?=$token;?>";
var loaded_at = new Date().getTime();

var allops = ["!","~", "*","%","/", "+","-", "<<",">>", "&","^","|"];

function resultRow(html, display, key, stats, limit) {
    if (key in stats && stats[key] != 0) {
        html.push('<tr><th>',display,'</th><td>');
        html.push(stats[key]);
        if (key in limit && limit[key] >= 0) {
            var tmp = limit[key];
            if (limit[key] < stats[key]) html.push(' (<span class="error">limit: ', tmp,'</span>)');
            else                           html.push(' (<span class="good">limit: ', tmp,'</span>)');
        }
        html.push('</td></tr>');
    }
} 

function showResults(score, stats, limits) {
    var html = [
        'As time of last submission, your results were:',
        '<table><tbody>',
        '<tr><th>Score</th><td>', score, '%</td></tr>'
    ];
    resultRow(html, 'Total ops', 'ops', stats, limits);
    resultRow(html, 'Const bits', 'const', stats, limits);

    for(var i=0; i<allops.length; i+=1) {
        resultRow(html, '<code>'+allops[i]+'</code>', allops[i], stats, limits)
    }
    document.getElementById('results').innerHTML = html.join('');
}

function formatSummaryLine(html, k, v) {
    html.push('<tr><td><input type="button" value="',k,
        '" onclick="request(\'',k,'\')"></td><td>',
        v === null ? 'not started' : v.score+'%',
        '</td><td><input type="button" value="',k,
        '" onclick="scoreboard(\'',k,'\')"></td></tr>');
}

function connect() {
    setText("connecting "+user+"...");
    socket = new WebSocket(getBaseURL() + "/ws");
    socket.onopen = function() {
        setText("connected; live updates enabled");
        socket.send(JSON.stringify({user:user, token:token, course:"<?=basename(dirname($_SERVER['SCRIPT_FILENAME']))?>"}));
    }
    socket.onmessage = function(message) {
        console.log("message: " + message.data);
        var data = JSON.parse(message.data);
        var kind = data["type"];
        delete data["."];
        if (kind == 'error') {
            console.log(data.message);
            setText('ERROR: ' + data.message);
        } else if (kind == "welcome") {
            socket.send(JSON.stringify({req:'status'}));
            setText(data['due'])
        } else if (kind == "board") {
            var html = [
                '<h1>',data['task'],'</h1>',
                '<style>tbody th { text-align: left; } thead th, td { text-align: center; padding: 0ex 1ex; }</style>',
                '<table><thead><tr><th>Nickname</th><th>Total Ops</th><th>Const bits</th>'
            ];
            for(var i=0; i<allops.length; i+=1) html.push('<th><tt>',allops[i],'</tt></th>');
            html.push('</tr></thead><tbody>');
            for(var k in data['board']) {
                html.push('<tr><th>',k.replace(/[^-_A-Za-z0-9 ]/g, ''),'</th>');
                if ('ops' in data.board[k].stats) html.push('<td>',data.board[k].stats.ops,'</td>');
                else html.push('<td/>');
                if ('const' in data.board[k].stats) html.push('<td>',data.board[k].stats.const,'</td>');
                else html.push('<td/>');
                for(var i=0; i<allops.length; i+=1) 
                    if (allops[i] in data['board'][k].stats && data.board[k].stats[allops[i]] != 0)
                        html.push('<td>',data['board'][k].stats[allops[i]],'</td>');
                    else
                        html.push('<td></td>');
                html.push('</tr>');
            }
            html.push('</tbody></table>');
            html.push('<input type="button" onclick="main()" value="back to index"></input>');
            setPage(html);
        } else if (kind == "you") {
            var html = ['<table><thead><tr><th>Task</th><th>Status</th><th>Scoreboard</th></tr></thead><tbody>'];
            data['task_groups'].forEach(group => {
                if (group['name'] != '') {
                    html.push('<tr><th class="taskgroup" colspan="3">', group['name'], '</th></tr>');
                }
                group['tasks'].forEach(task => {
                    console.log('handling task ' + task + ' ' + data['status'][task]);
                    formatSummaryLine(html, task, data['status'][task]);
                });
            });
            html.push('</tbody></table>');
            html.push(
                '<p>Name to show on scoreboards: <input type="text" id="nick" name="nick" value="',
                data.nickname,
                '"/> <input type="button" value="Change nickname" onclick="nickname()"/><br/>Note: do not use a name that a fellow student might reasonably consider offensive.</p>'
            );
            setPage(html);
        } else if (kind == "task") {
            var html = [
                '<h1>',data.task,'</h1>',
                '<p>',md.makeHtml(data.description),'</p>',
                '<p><strong>Provided input(s):</strong> <code>',
                data.provided.join('</tt> and <tt>'),
                '</code></p>',
                '<p><strong>Permitted:</strong> ',('ops' in data.limits ? data.limits.ops : 'any number of'),' operations (may use '
            ];
            for(var i=0; i<allops.length; i+=1)
                if (data.limits[allops[i]] < 0) html.push('<code>',allops[i],'</code>',', ');
                else if (data.limits[allops[i]] > 0) html.push(data.limits[allops[i]], ' <code>',allops[i],'</code>',', ');
            html.pop(); // ', '
            html.push(')');
            if ('const' in data.limits && data.limits['const'] >= 0) {
                if (data.limits['const'] == 0) html.push(' and no constants');
                else html.push('and up to ', data.limits['const'], '-bit constants');
            }
            html.push(
                '</p>',
                '<textarea id="code" name="code" rows="20" cols="60" onchange="note_change()"></textarea><br/>',
                '<input type="button" onclick="submit(\'',data.task,'\')" value="submit code"></input>',
                '<div id="compile-error" class="compile"></div>',
                '<div id="results"></div>',
            );
            setPage(html);
            if (data.code) // this way to ensure escaping...
                document.getElementById('code').appendChild(document.createTextNode(data.code));
            if (data.results) // this way to avoid code duplication
                showResults(data.results.score, data.results.stats, data.limits);
        } else if (kind == "results") {
            var error = document.getElementById('compile-error');
            error.innerHTML = "";
            if(data.score == 0) {
                var res = document.getElementById('results');
                var html = [
                    '<p>', data.message, '</p>',
                    '<table><thead><th>Variable</th><th>Value</th></thead><tbody>'
                ];
                for(var n in data.vars) if (n != '__ignored__') {
                    var tmp = new Uint32Array(1);
                    tmp[0] = data.vars[n];
                    html.push('<tr><td><code>',n,'</code></td><td>',tmp[0].toString(2),'<sub>2</sub> (',data.vars[n],')</td></tr>');
                }
                html.push('</tbody></table>');
                res.innerHTML = html.join('');
            } else {
                showResults(data.score, data.stats, data.limits);
            }
        } else if (kind == "compile-error") {
            var error = document.getElementById('compile-error');
            error.innerHTML = "ERROR: " + data.message;
        } else if (kind == "reauthenticate") {
            setText("connection closed; save your work outside this window and then reload page to make a new connection.");
            //window.location.reload(false);
            //setText("Unexpected message \""+kind+"\" (please report this to the professor if it stays on the screen)");
        } else {
            setText("Unexpected message \""+kind+"\" (please report this to the professor)");
        }
    }
    socket.onclose = function() {
        setText("connection closed; save your work outside this window and then reload page to make a new connection.");
        //setText("connection closed; reload page to make a new connection.");
        //var now = new Date().getTime();
        //if (loaded_at +10*1000 < now) // at least 10 seconds to avoid refresh frenzy
            //setTimeout(function(){window.location.reload(false);}, 10);
    }
    socket.onerror = function() {
        setText("error connecting to server");
    }
}

function nickname() {
    console.log('nickname',name);
    var name = document.getElementById('nick').value;
    socket.send(JSON.stringify({req:'nickname',name:name}));
}
function submit(name) {
    console.log('submit',name);
    var code = document.getElementById('code').value;
    socket.send(JSON.stringify({req:'code',code:code,task:name}));
}
function request(name) {
    console.log('request',name);
    socket.send(JSON.stringify({req:'task',task:name}));
}
function scoreboard(name) {
    console.log('scoreboard',name);
    socket.send(JSON.stringify({req:'scores',task:name}));
}

function getBaseURL() {
    var wsurl = "wss://" + window.location.hostname+':23101'
    return wsurl;
}

function setText(text) {
    console.log("text: ", text);
    if (socket && socket.readyState >= socket.CLOSING) {
        text = "(unconnected) "+text;
        document.title = "(unconnected) Office Hours";
    }
    document.getElementById("console").innerHTML += "\n"+text;
}
function setPage(html) {
    if(typeof(html) == 'string') document.getElementById('content').innerHTML = html;
    else document.getElementById('content').innerHTML = html.join('');
}

//--></script></head>
<body onload="connect()">
    <!--<div style="display: table; margin: auto; padding: 1em; font-size: 200%; background:rgba(255,0,0,0.25);">This assignment is now closed.</div>-->
<div id="content"></div>
<pre id="console">(client-server status log)</pre>
<a href="<?=$_SERVER['SCRIPT_NAME']?>">Click here to reload page (loses all unsubmitted work)</a>
</body>
