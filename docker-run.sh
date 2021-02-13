#!/usr/bin/env sh

set -e

redis-server --daemonize yes
/app/service.py
