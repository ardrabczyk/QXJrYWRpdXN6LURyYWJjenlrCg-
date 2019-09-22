#!/usr/bin/env sh

set -e

/usr/bin/redis-server /etc/redis.conf --supervised systemd --daemonize yes
/app/service.py
