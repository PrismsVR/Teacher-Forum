#!/bin/bash

set -e

# follow https://github.com/redis/docker-library-redis/blob/master/docker-entrypoint.sh pattern of changing user permissions at the last moment
# this is needed to support correct permissions in volumes.
# allow the container to be started with `--user`
echo "please wait, docker-entrypoint setting up secure nodebb user context..."
gosu root chown -R ${USER}:${USER} /usr/src/app/build/ # public/
gosu root chown -R ${USER}:${USER} /usr/src/app/public/uploads/
# chown -R ${USER}:${USER} /usr/src/app/

# Execute main function
gosu ${USER} entrypoint.sh "$@"
