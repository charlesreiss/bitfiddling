#!/bin/bash

cd /opt/cs3330-bitlab
date >> logs/runlog

# newgrp instructors # execs so lose context
pgrep -a bit3330fiddle >/dev/null && exit 0

if [ "$(ls -t source | head -1)" -nt bit3330fiddle ]; then dub build -b release >>buildlog 2>>buildlog; fi
nohup bash restart_on_segfault.sh ./bit3330fiddle >>logs/runlog 2>>logs/runlog </dev/null &
