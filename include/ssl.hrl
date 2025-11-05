%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% Default SSL options common to client and server
-define(SSL_DEFAULT_COMMON_OPTS, [binary,
        {packet,0},
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
        {ciphers,[
                %% TLS 1.3 cipher suites (most secure, AEAD only)
                "TLS_AES_256_GCM_SHA384",
                "TLS_AES_128_GCM_SHA256",
                "TLS_CHACHA20_POLY1305_SHA256",
                %% TLS 1.2 cipher suites (secure, forward secrecy with AEAD)
                "ECDHE-ECDSA-AES256-GCM-SHA384",
                "ECDHE-RSA-AES256-GCM-SHA384",
                "ECDHE-ECDSA-AES128-GCM-SHA256",
                "ECDHE-RSA-AES128-GCM-SHA256",
                "ECDHE-ECDSA-CHACHA20-POLY1305",
                "ECDHE-RSA-CHACHA20-POLY1305",
                %% TLS 1.2 with SHA384/SHA256 (forward secrecy, non-AEAD but acceptable)
                "ECDHE-ECDSA-AES256-SHA384",
                "ECDHE-RSA-AES256-SHA384",
                "ECDHE-ECDSA-AES128-SHA256",
                "ECDHE-RSA-AES128-SHA256"
        ]},
        {secure_renegotiate,true},
        {reuse_sessions,true},
        {versions,['tlsv1.3', 'tlsv1.2']},
        {verify,verify_peer},
        {hibernate_after,600000},
        {active,false}]).

-define(SSL_DEFAULT_SERVER_OPTS, [{fail_if_no_peer_cert,true},
        {log_alert,false},
        {client_renegotiation,true}]).

-define(SSL_DEFAULT_CLIENT_OPTS, [{server_name_indication,disable},
        {depth,99}]).
