#!/usr/bin/env bash

if [ $# -lt 1 ]
then
    printf "USAGE: %s <service_conf_file>\n" "$0" >&2
    exit 1
fi

if ! command -v curl >/dev/null
then
    printf "curl not in \$PATH. Exiting.\n" >&2
    exit 2
fi

if ! command -v jq >/dev/null
then
    printf "jq not in \$PATH. Exiting.\n" >&2
    exit 2
fi

conf="$1"

if [ ! -e "$conf" ]
then
    printf "%s does not exist. Exiting.\n" "$conf" >&2
    exit 3
fi

. <(sed -E 's,\s+,,g' "$conf")

green="\033[32m"
red="\033[31m"
normal="\033[00m"

# 0 check is service is running at all
test=0
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" >/dev/null 2>&1
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure. Make sure you ran the service"
    exit 3
fi
printf "${green}%s${normal}\n" "success"

# we will need a temporary files for the rest of the tests
temp="$(mktemp)"

# 1. add new id, use correct JSON
test=1
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":"https://httpbin.org/range/2","interval":3}' > "$temp"

if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 200 OK" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 200 OK, got " "$received_header"
    exit 4
fi

# check id that service has returned
new_id="$(tail -n 1 "$temp" | jq '.id'  2>/dev/null)"
if [ -z "$new_id" ]
then
    printf "${red}%s${normal}\n" "failure. Wrong id returned"
    exit 4
fi
printf "${green}%s${normal}\n" "success"

# 2. add new id, use incorrect JSON
test=2
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":"https://httpbin.org/range/2","interval":"3"}' > "$temp"
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 400 Bad Request" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 400 Bad Request, got " "$received_header"
    exit 4
fi
printf "${green}%s${normal}\n" "success"

# 3. add new id, too big payload
test=3
printf "Running test %d: " "$test"
expected_return=0
payload="$(printf '%*s' "$REQUEST_MAX_SIZE" | tr ' ' a)"
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":'"\"$payload\""',"interval":3}' > "$temp"
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 413 Request Entity Too Large" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 413 Request Entity Too Large, got " "$received_header"
    exit 4
fi
printf "${green}%s${normal}\n" "success"
