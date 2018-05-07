#!/bin/bash

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" SIGTERM SIGINT

stop()
{
  # We're here because we've seen SIGTERM, likely via a Docker stop command or similar
  # Let's shutdown cleanly
  echo "SIGTERM caught, terminating NFS process(es)..."
  /usr/sbin/exportfs -uav
  pid1=$(pidof rpc.nfsd)
  pid2=$(pidof rpc.mountd)
  kill -TERM $pid1 $pid2 > /dev/null 2>&1
  echo "Terminated."
  exit
}

if [ -z "${SHARED_DIRECTORY}" ]; then
  echo "The SHARED_DIRECTORY environment variable is missing or null, exiting..."
  exit 1
fi
if [ -z "${PERMITTED}" ]; then
  echo "The PERMITTED environment variable is missing or null, defaulting to '*'."
  echo "Any client can mount."
fi
if [ -z "${READ_ONLY}" ]; then
  echo "The READ_ONLY environment variable is missing or null, defaulting to 'rw'"
  echo "Clients have read/write access."
fi
if [ -z "${SYNC}" ]; then
  echo "The SYNC environment variable is missing or null, defaulting to 'async'".
  echo "Writes will not be immediately written to disk."
fi

# This loop runs till until we've started up successfully
while true; do

  # Check if NFS is running by recording it's PID (if it's not running $pid will be null):
  pid=$(pidof rpc.mountd)

  # If $pid is null, do this to start or restart NFS:
  while [ -z "$pid" ]; do
    echo "Starting Confd population of files..."
    /usr/bin/confd -version
    /usr/bin/confd -onetime
    echo ""
    echo "Displaying /etc/exports contents..."
    cat /etc/exports
    echo ""

    # Normally only required if v3 will be used
    # But currently enabled to overcome an NFS bug around opening an IPv6 socket
    echo "Starting rpcbind..."
    /sbin/rpcbind -w
    echo "Displaying rpcbind status..."
    /sbin/rpcinfo

    # Only required if v3 will be used
    # /usr/sbin/rpc.idmapd
    # /usr/sbin/rpc.gssd -v
    # /usr/sbin/rpc.statd

    echo "Starting NFS in the background..."
    /usr/sbin/rpc.nfsd --debug 8 --no-udp --no-nfs-version 2 --no-nfs-version 3
    echo "Exporting File System..."
    /usr/sbin/exportfs -rv
    /usr/sbin/exportfs
    echo "Starting Mountd in the background..."
    /usr/sbin/rpc.mountd --debug all --no-udp --no-nfs-version 2 --no-nfs-version 3
# --exports-file /etc/exports

    # Check if NFS is now running by recording it's PID (if it's not running $pid will be null):
    pid=$(pidof rpc.mountd)

    # If $pid is null, startup failed; log the fact and sleep for 2s
    # We'll then automatically loop through and try again
    if [ -z "$pid" ]; then
      echo "Startup of NFS failed, sleeping for 2s, then retrying..."
      sleep 2
    fi

  done

  # Break this outer loop once we've started up successfully
  # Otherwise, we'll silently restart and Docker won't know
  echo "Startup successful."
  break

done

while true; do

  # Check if NFS is STILL running by recording it's PID (if it's not running $pid will be null):
  pid=$(pidof rpc.mountd)
  # If it is not, lets kill our PID1 process (this script) by breaking out of this while loop:
  # This ensures Docker observes the failure and handles it as necessary
  if [ -z "$pid" ]; then
    echo "NFS has failed, exiting, so Docker can restart the container..."
    break
  fi

  # If it is, give the CPU a rest
  sleep 1

done

sleep 1
exit 1
