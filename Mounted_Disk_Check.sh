#!/usr/bin/env bash

# used to capture all mount points, less exclusions

### Lists all mounts using df
### Excludes defined mount points monitored elsewhere
### Collects perfdata for all included mounts
### Plugin output tells you which included mount is over threshold, if any

WARN=96
CRIT=98

# regex exclusion, if start and end of string (^,$) are not called out, unforeseen exclusions may occur. Omit where necessary
EXCLUDE='^/tmp$|^/boot|^/apps$|^/dev/shm$|^/home$|^/run$|^/var$|^/opt$|^/sys/fs/cgroup$|^memory$|^Memory$|^Swap$|^/mongoshare/.snapshot$|^/emedia/.snapshot$'

# CLI arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--warning) WARN="$2"; shift 2;;
        -c|--critical) CRIT="$2"; shift 2;;
        -e|--exclude) EXCLUDE="$2"; shift 2;;
        -d|--debug) DEBUG=true; shift;;
        *) echo "Unknown argument: $1"; exit 3;;
    esac
done

status=0
perfdata=""
msgs=()
raw_msgs=()

# create a tmpfile to store df output because shell within shell was causing issues
TMPFILE=$(mktemp)
/bin/df --output=source,size,used,avail,pcent,target | tail -n +2 > "$TMPFILE"

# Read and process each mount from df
while read -r fs size used avail usep mnt; do
    pct=${usep%\%}
    [[ -z "$pct" || -z "$mnt" ]] && continue

    # Skip excluded mount points
    if echo "$mnt" | grep -Eq "$EXCLUDE"; then
        [[ "$DEBUG" == true ]] && echo "DEBUG: Skipping excluded mount $mnt" >&2
        continue
    fi

    [[ "$DEBUG" == true ]] && echo "DEBUG: Checking mount $mnt (use=${pct}%)" >&2


    if   (( pct >= CRIT )); then s=2; label=CRITICAL
    elif (( pct >= WARN )); then s=1; label=WARNING
    else                        s=0; label=OK
    fi

    (( s > status )) && status=$s

    perfdata+=" '$mnt'=${pct}%;${WARN};${CRIT};0;100 "
    raw_msgs+=("$label $mnt at ${pct}%")

    if (( s > 0 )); then
	msgs+=("$label $mnt at ${pct}%")
    fi
done < "$TMPFILE"
rm -f "$TMPFILE"

# Plugin output
if   (( status == 0 )); then
    echo "OK - All Selected Mounts < ${WARN}% |${perfdata}"
    exit 0
elif (( status == 1 )); then
    echo "WARNING - ${msgs[*]} |${perfdata}"
    exit 1
else
    echo "CRITICAL - ${msgs[*]} |${perfdata}"
    exit 2
fi

