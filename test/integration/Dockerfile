# Dockerfile to test gen_rpc via proper distributed nodes
FROM erlang:29
LABEL org.opencontainers.image.authors="Panagiotis PJ Papadomitsos <pj@ezgr.net>"
WORKDIR /gen_rpc
ENV TERM=xterm-256color
# All the nodes share the same Erlang cookie
RUN echo gen_rpc > /root/.erlang.cookie && chmod 600 /root/.erlang.cookie
COPY . .
RUN rebar3 as dev compile && rebar3 as test compile
