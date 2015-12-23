#
# Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
#
# Build targets:
#
# all: 			rebar3 as dev do compile
# shell:		rebar3 as dev do shell
# clean: 		rebar3 as dev do clean
# distclean: 	rebar3 as dev do clean -a
#               and explicitly delete other build artifacts
# test: 		rebar3 as test do ct -v, cover
# dialyzer: 	rebar3 as test do dialyzer
# xref:			rebar3 as dev do xref
# dist: 		rebar3 as test do compile, ct -v, xref, dialyzer, cover
# spec: 		Runs typer to generate source code specs
# rebar: 		Downloads a precompiled rebar3 binary and places it inside the project. The rebar binary is .gitignored.
#				This step is always run first on build targets.
# tags:			Builds Emacs tags file
# epmd:			Runs the Erlang port mapper daemon, required for running the app and tests
#

# .DEFAULT_GOAL can be overridden in custom.mk if "all" is not the desired
# default

.DEFAULT_GOAL := all

# Build targets
.PHONY: all test dialyzer xref spec dist

# Run targets
.PHONY: shell

# Misc targets
.PHONY: clean testclean distclean tags rebar

PROJ = $(shell ls -1 src/*.src | sed -e 's/src//' | sed -e 's/\.app\.src//' | tr -d '/')

custom_rules_file = $(wildcard custom.mk)
ifeq ($(custom_rules_file),custom.mk)
    include custom.mk
endif

# =============================================================================
# verify that the programs we need to run are installed on this system
# =============================================================================
ERL = $(shell which erl)
TYPER = $(shell which typer)

ifeq ($(ERL),)
$(error "Erlang not available on this system")
endif

# If there is a rebar in the current directory, use it
ifeq ($(wildcard rebar3),rebar3)
REBAR = $(CURDIR)/rebar3
endif

# And finally, prep to download rebar if all else fails
ifeq ($(REBAR),)
REBAR = $(CURDIR)/rebar3
endif

REBAR_URL = https://s3.amazonaws.com/rebar3/rebar3

PLT_FILE = $(CURDIR)/_plt/*plt

# =============================================================================
# Build targets
# =============================================================================

all: $(REBAR)
	@REBAR_PROFILE=dev $(REBAR) do compile

test: $(REBAR) epmd
	@REBAR_PROFILE=test $(REBAR) do ct -v -c

benchtest: $(REBAR) epmd
	@cd _build/default/lib/basho_bench && ./build_test_tool.sh && cd ../../../..
	@./start_target.sh

dialyzer: $(REBAR)
	@REBAR_PROFILE=dev $(REBAR) do dialyzer | fgrep -v -f $(CURDIR)/dialyzer.ignore

xref: $(REBAR)
	@REBAR_PROFILE=dev $(REBAR) do xref

spec: dialyzer
	@$(TYPER) --annotate-inc-files -I ./include --plt $(PLT_FILE) -r src/

dist: $(REBAR) test
	@REBAR_PROFILE=dev $(REBAR) do dialyzer, xref

# =============================================================================
# Run targets
# =============================================================================

shell: $(REBAR) epmd
	@REBAR_PROFILE=dev $(REBAR) do shell --name gen_rpc@127.0.0.1

# =============================================================================
# Misc targets
# =============================================================================

clean: $(REBAR)
	@$(REBAR) clean
	@rm -f rebar.lock

distclean: $(REBAR)
	@rm -rf _build _plt .rebar Mnesia* mnesia* log/ data/ temp-data/ rebar.lock
	@find . -name erl_crash.dump -type f -delete
	@$(REBAR) clean -a

testclean:
	@rm -fr _build/test && rm -rf ./test/*.beam
	@find log/ct -maxdepth 1 -name ct_run* -type d -cmin +360 -exec rm -fr {} \;

epmd:
	@pgrep epmd 2> /dev/null > /dev/null || epmd -daemon || true

$(REBAR):
	@curl -Lo rebar3 $(REBAR_URL) || wget $(REBAR_URL)
	@chmod a+x rebar3
	@$(CURDIR)/rebar3 update

tags:
	find src _build/default/lib -name "*.[he]rl" -print | etags -
