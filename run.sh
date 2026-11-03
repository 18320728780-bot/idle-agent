#!/bin/sh
set -a
. "$(dirname "$0")/env"
set +a
exec python3 -m idle.core --tick
