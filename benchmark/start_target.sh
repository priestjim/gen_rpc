#!/bin/bash
echo "Start a target server"
export TARGET_NODE_NAME=gen_rpc_target@127.0.0.1
export TEST_SYS_COOKIE=genrpc
export LIBDIR=./_build/default/lib/*/ebin

echo "Starting gen_rpc Bench Test"
eval "erl \
    -name \"${TARGET_NODE_NAME}\" \
    -setcookie \"${TEST_SYS_COOKIE}\" \
    -pa ${LIBDIR} -eval \"application:ensure_all_started(gen_rpc)"\"
