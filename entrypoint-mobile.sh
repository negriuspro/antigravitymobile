#!/bin/sh
set -e
nginx -g 'daemon off;' &
exec uvicorn main:app --host 0.0.0.0 --port 8000
