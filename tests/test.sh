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

# 1. check is service is running at all
test=1
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" >/dev/null 2>&1
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure. Make sure you ran the service"
    exit 3
fi
printf "${green}%s${normal}\n" "success"

# we will need a temporary file for the rest of the tests
temp="$(mktemp)"

# 2. add new id, use correct JSON
test=$((++test))
printf "Running test %d: " "$test"
expected_return=0
worker_interval=3
worker_expected_response='"ab"'
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":"https://httpbin.org/range/2","interval":'"$worker_interval"'}' > "$temp"

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
worker_new_id="$(tail -n 1 "$temp" | jq '.id'  2>/dev/null)"
if [ -z "$worker_new_id" ]
then
    printf "${red}%s${normal}\n" "failure. Wrong id returned"
    exit 4
fi
printf "${green}%s${normal}\n" "success"

# 3. add new id, use incorrect JSON
test=$((++test))
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

# 4. add new id, too big payload
test=$((++test))
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

# 5. add new id, malformatted URL
test=$((++test))
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":"https//httpbin.org/range/15","interval":3}' > "$temp"
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 400 Bad Request" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 400 Bad Request got " "$received_header"
    exit 4
fi
printf "${green}%s${normal}\n" "success"

# 6. add new id, pass interval as a string
test=$((++test))
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS" -X POST -d '{"url":"https://httpbin.org/range/16","interval":"3"}' > "$temp"
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 400 Bad Request" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 400 Bad Request got " "$received_header"
    exit 4
fi
printf "${green}%s${normal}\n" "success"

# 7. test worker we set up in 2nd test

# sleep for 2x $worker_interval and an extra 1 second to let worker download data at
# least 2 times
sleep "$worker_interval"
sleep "$worker_interval"
sleep 1
test=$((++test))
printf "Running test %d: " "$test"
expected_return=0
curl -si 127.0.0.1:"$PORT"/"$ENDPOINT_BASE_ADDRESS"/"$worker_new_id"/history > "$temp"
if [ ! $? -eq "$expected_return" ]
then
    printf "${red}%s${normal}\n" "failure"
    exit 4
fi

# check http header
received_header="$(head -1 "$temp" | tr -d '\r')"
if [ "$received_header" != "HTTP/1.1 200 OK" ]
then
    printf "${red}%s%s${normal}\n" "failure. Expected HTTP/1.1 200 OK got " "$received_header"
    exit 4
fi

# check if correct data is being downloaded at correct intervals
first_timestamp="$(tail +7 "$temp" | jq '.[0].created_at')"
first_response="$(tail +7 "$temp" | jq '.[0].response')"

second_timestamp="$(tail +7 "$temp" | jq '.[1].created_at')"
second_response="$(tail +7 "$temp" | jq '.[1].response')"

for i in "$first_response" "$second_response"
do
    if [ "$i" != "$worker_expected_response" ]
    then
	printf "${red}failure. Expected response == %s, got %s${normal}\n" "$worker_expected_response" "$i"
	exit 4
    fi
done

timestamp_difference="$(echo "$second_timestamp" - "$first_timestamp" | bc)"
timestamp_difference_lower_limit=2.8
timestamp_difference_upper_limit=3.2

if [ ! "$(echo "$timestamp_difference_upper_limit > $timestamp_difference && timestamp_difference_lower_limit < $timestamp_difference" | bc)" -eq 1 ]
then
    printf "${red}failure. Timestamp difference not within (%s,%s) limit${normal}\n" "$timestamp_difference_lower_limit" "$timestamp_difference_upper_limit"
    exit 4
fi

printf "${green}%s${normal}\n" "success"
