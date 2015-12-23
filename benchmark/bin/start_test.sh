#!/bin/bash
echo on
echo "Start a test"
#TARGET_NODE_NAME=gen_rpc_benchmark@127.0.0.1
#TEST_SYS_COOKIE=genrpc
read TARGET_NODE_NAME
read TEST_SYS_COOKIE

rm -rf ./tests/*
./basho_bench -N ${TARGET_NODE_NAME} -C ${TEST_SYS_COOKIE} $1

