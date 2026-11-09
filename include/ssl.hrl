%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% ECDSA only signature algorithms
-define(SSL_SIGNATURE_ALGS, [ecdsa_secp384r1_sha384,ecdsa_secp256r1_sha256,ecdsa_secp521r1_sha512]).

%%% Default SSL options common to client and server
-define(SSL_DEFAULT_COMMON_OPTS, [binary,
        {packet,4}, % Length-prefixed frames, TLS is a byte stream that splits and coalesces messages
        {header,0},
        {exit_on_close,true},
        {nodelay,true}, % Send our requests immediately
        {send_timeout_close,true}, % When the socket times out, close the connection
        {delay_send,false}, % Scheduler should favor timely delivery
        {linger,{true,2}}, % Allow the socket to flush outgoing data for 2" before closing it - useful for casts
        {reuseaddr,true}, % Reuse local port numbers
        {keepalive,true}, % Keep our channel open
        {tos,72}, % Deliver immediately
        {active,false},
        %% SSL options
        %% TLS 1.3 AEAD cipher suites, the key exchange is negotiated
        %% separately through the supported groups
        {ciphers,["TLS_AES_256_GCM_SHA384",
                "TLS_CHACHA20_POLY1305_SHA256",
                "TLS_AES_128_GCM_SHA256"]},
        %% Hybrid post-quantum (ML-KEM) and elliptic curve key exchange only,
        %% filtered at runtime against what the running OTP release supports
        {supported_groups,gen_rpc_helper:get_ssl_groups()},
        %% ECDSA only, both for the handshake and for the certificate chain
        {signature_algs,?SSL_SIGNATURE_ALGS},
        {signature_algs_cert,?SSL_SIGNATURE_ALGS},
        {versions,['tlsv1.3']},
        {verify,verify_peer},
        {hibernate_after,600000}]).

-define(SSL_DEFAULT_SERVER_OPTS, [{fail_if_no_peer_cert,true},
        {log_alert,false},
        {honor_ecc_order,true},
        {honor_cipher_order,true}]).

-define(SSL_DEFAULT_CLIENT_OPTS, [{server_name_indication,disable},
        {depth,99}]).
