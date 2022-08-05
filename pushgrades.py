from os.path import exists, join
from os import makedirs, umask, chmod
umask(0)

import json
import time
zone = time.strftime('%Z', time.localtime())


now = time.time()
def strptime(text, fmt):
    import calendar
    return calendar.timegm(time.strptime(text+' '+zone, fmt+' %Z'))

tasks = [
    # (dir, name, tasks, num_needed)
    ['/var/www/html/cso1/','HW01',('subtract','bottom','anybit','bitcount'),4],
    ['/var/www/html/cs3330/','Lab02',('subtract','bottom','endian','bitcount'),4],
    ['/var/www/html/cs3330/','HW02',('getbits','anybit','reverse','fiveeighths'),3],
]



for task in tasks:
    with open(task[0]+'meta/assignments.json') as fh:
        data = json.load(fh)[task[1]]
        due = strptime(data['due'],'%Y-%m-%d %H:%M')
        late = (24*60*60*len(data.get('late-policy',[])))
        task.extend((due,late))

results = {}
longres = {}
with open('logs/scores.log') as f:
    for line in f:
        obj = json.loads(line)
        for user, report in obj.items():
            if user[0] == '.': continue
            for task, res in report.items():
                new = res.get('score',0)
                old = results.setdefault(user, {}).setdefault(task, 0)
                if new > 0:
                    longres.setdefault(user, {}).setdefault(task, []).append((new, strptime(obj.get('.date','2019-12-12T23:59:55')[:19], '%Y-%m-%dT%H:%M:%S')))
                if new >= old:
                    results[user][task] = new

for u in results:
    for base,slug,opts,num,due,pad in tasks:
        if exists(join(base,'users',u+'.json')):
            if exists(join(base,'uploads',slug,'.extension')):
                due = strptime(json.load(open(join(task['base'],'uploads',task['slug'],'.extension')))['due'], '%Y-%m-%d %H:%M')
            
            # retcon version
            earned = []
            for o in opts:
                got = 0
                for e,t in longres.get(u,{}).get(o,[]):
                    # print(u, due+pad, t)
                    if due + pad >= t and e > got: got = e
                earned.append(got)
            scores = sorted(earned)

            # live version
            # if due + pad < now: continue
            
            # scores = sorted([results[u].get(_,0) for _ in opts])
            ratio = sum(scores[-num:])/num/100
            notes = '\n'.join(['{}% on {}'.format(results[u].get(_,0),_) for _ in opts])

            makedirs(join(base,'uploads',slug,u), mode=0o777, exist_ok=True)
            json.dump({
                'kind':'percentage',
                'ratio':ratio,
                'comments':notes
            }, open(join(base,'uploads',slug,u,'.grade'), 'w'))
            
            print(base,slug,u,ratio)
