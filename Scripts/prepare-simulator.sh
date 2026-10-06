#!/bin/bash
#
# Prepares the simulator that a CI job builds and tests on, and prints its udid.
#
#   Scripts/prepare-simulator.sh <device type name> <iOS version>
#
#   udid="$(Scripts/prepare-simulator.sh "iPhone 17" 26.5)"
#
# The newest available iOS runtime of that version is used, or of a patch release of it: an
# image keeps its label when its runtime moves to 26.5.1. The available device of that name on
# that runtime is used; when the image has none, the script creates it from the device type. The
# device is booted, and the script waits until the boot completes. A job passes the udid to
# xcodebuild as id=<udid>, never a name and an OS: a hosted image can list a runtime with no
# device in it, and a destination that names a missing device fails before the build (exit 70).
#
# Standard output is the udid and nothing else. Standard error carries the progress, the runtime
# used and whether the device was created.
#
# Exit codes: 0 the simulator is booted. 1 no available iOS runtime of that version is listed
# within five minutes, the device type does not exist or the runtime does not support it, or a
# step on the device failed. 2 wrong usage.

set -euo pipefail

readonly WAIT_SECONDS=300
readonly POLL_SECONDS=10

fail() {
    echo "prepare-simulator: $*" >&2
    exit 1
}

if [ "$#" -ne 2 ] || [ -z "$1" ] || ! [[ "$2" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "usage: Scripts/prepare-simulator.sh <device type name> <iOS version>, such as \"iPhone 17\" 26.5" >&2
    exit 2
fi
DEVICE_NAME="$1"
IOS_VERSION="$2"

# Prints the runtime identifier, the runtime version, the device type identifier and the udid of
# an existing device, tab-separated; the udid is empty when there is none. Exit 3: no available
# iOS runtime of that version is listed yet. Exit 4: no device type of that name. Exit 5: the
# runtime does not support that device type.
resolve() {
    xcrun simctl list -j | python3 -c '
import json
import sys

name, version = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
ios = "com.apple.CoreSimulator.SimRuntime.iOS-"
runtimes = [runtime for runtime in data["runtimes"]
            if runtime["isAvailable"] and runtime["identifier"].startswith(ios)
            and (runtime["version"] == version or runtime["version"].startswith(version + "."))]
if not runtimes:
    sys.exit(3)
runtime = max(runtimes, key=lambda item: [int(part) for part in item["version"].split(".")])
types = [device_type for device_type in data["devicetypes"] if device_type["name"] == name]
if not types:
    sys.exit(4)
supported = [device_type["identifier"] for device_type in runtime["supportedDeviceTypes"]]
if types[0]["identifier"] not in supported:
    sys.exit(5)
existing = [device["udid"] for device in data["devices"].get(runtime["identifier"], [])
            if device["name"] == name and device["isAvailable"]]
print("\t".join([runtime["identifier"], runtime["version"], types[0]["identifier"],
                 existing[0] if existing else ""]))
' "$DEVICE_NAME" "$IOS_VERSION"
}

# CoreSimulator lists its runtimes some time after the image starts, so the runtime is polled for.
started=$SECONDS
announced=""
while :; do
    status=0
    resolution="$(resolve)" || status=$?
    if [ "$status" -ne 3 ]; then
        break
    fi
    if [ -z "$announced" ]; then
        echo "prepare-simulator: no available iOS $IOS_VERSION runtime yet, waiting up to $WAIT_SECONDS seconds" >&2
        announced=1
    fi
    if [ $((SECONDS - started)) -ge "$WAIT_SECONDS" ]; then
        echo "prepare-simulator: no available iOS $IOS_VERSION runtime after $WAIT_SECONDS seconds. The runtimes are:" >&2
        xcrun simctl list runtimes >&2
        exit 1
    fi
    sleep "$POLL_SECONDS"
done

case "$status" in
    0) ;;
    4)
        echo "prepare-simulator: there is no device type named $DEVICE_NAME. The device types are:" >&2
        xcrun simctl list devicetypes >&2
        exit 1
        ;;
    5)
        echo "prepare-simulator: $DEVICE_NAME is not supported by the iOS $IOS_VERSION runtime. The runtimes are:" >&2
        xcrun simctl list runtimes >&2
        exit 1
        ;;
    *)
        fail "could not read the simulator list (exit $status)"
        ;;
esac

IFS=$'\t' read -r RUNTIME_ID RUNTIME_VERSION DEVICE_TYPE_ID UDID <<< "$resolution"
echo "prepare-simulator: using iOS $RUNTIME_VERSION ($RUNTIME_ID)" >&2
if [ -n "$UDID" ]; then
    echo "prepare-simulator: the image has $DEVICE_NAME on iOS $RUNTIME_VERSION: $UDID" >&2
else
    echo "prepare-simulator: the image has no $DEVICE_NAME on iOS $RUNTIME_VERSION, creating one" >&2
    UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")" \
        || fail "could not create $DEVICE_NAME on iOS $RUNTIME_VERSION"
    echo "prepare-simulator: created $DEVICE_NAME: $UDID" >&2
fi
xcrun simctl bootstatus "$UDID" -b >&2 || fail "$DEVICE_NAME ($UDID) did not finish booting"
printf '%s\n' "$UDID"
