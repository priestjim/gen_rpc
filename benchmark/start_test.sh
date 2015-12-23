#!/bin/bash
echo on
echo "Start testing"
#TARGET_NODE_NAME=gen_rpc_benchmark@127.0.0.1
#TEST_SYS_COOKIE=genrpc
BASHOBENCHDIR=./_build/default/lib/basho_bench/
read TARGET_NODE_NAME
read TEST_SYS_COOKIE

rm -rf ./tests/*
echo "<path to>/basho_bench -N your_target_erlang-node_name -C your_erlang_cookie your_test_config"
${BASHOBENCHDIR}/basho_bench -N ${TARGET_NODE_NAME} -C ${TEST_SYS_COOKIE} $1

