#!/bin/bash

cd /opt/coa1-bithw
date >> logs/runlog

# newgrp instructors # execs so lose context
pgrep -a bitfiddle >/dev/null && exit 0

if [ "$(ls -t source | head -1)" -nt bitfiddle ]; then dub build -b release >>buildlog 2>>buildlog; fi
nohup bash restart_on_segfault.sh ./bitfiddle >>logs/runlog 2>>logs/runlog </dev/null &
