#!/bin/bash
export PATH=/home/zbrad/.local/bin:/usr/local/cuda-13.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /mnt/f/GitHub/raft
bash build.sh libraft tests
