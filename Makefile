#
# Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
#
# Build targets:
#
# all: 			    rebar3 as dev do compile
# shell:		    rebar3 as dev do shell
# clean: 		    rebar3 as dev do clean
# distclean:    rebar3 as dev do clean -a
#               and explicitly delete other build artifacts
# test: 		    rebar3 as test do ct -v, cover
# travis:       Run the proper tests/coveralls in travis
# dialyzer:     rebar3 as test do dialyzer
# xref:         rebar3 as dev do xref
# dist:         rebar3 as test do compile, ct -v -c, xref, dialyzer, cover
# spec:         Runs typer to generate source code specs
# rebar:        Downloads a precompiled rebar3 binary and places it inside the project. The rebar binary is .gitignored.
#               This step is always run first on build targets.
# tags:         Builds Emacs tags file
# epmd:         Runs the Erlang port mapper daemon, required for running the app and tests
#

# .DEFAULT_GOAL can be overridden in custom.mk if "all" is not the desired
# default

.DEFAULT_GOAL := all

PROJ = $(shell ls -1 src/*.src | sed -e 's/src//' | sed -e 's/\.app\.src//' | tr -d '/')

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

OTP_RELEASE = $(shell escript otp-release.escript)

PLT_FILE = $(CURDIR)/_plt/rebar3_$(OTP_RELEASE)_plt

# ======================
# Integration test logic
# ======================
ifneq ($(shell which docker 2> /dev/null),)

NODES ?= 3

.PHONY: integration
integration:
	@export NODES=$(NODES) && cd test/integration && bash -c "./integration-tests.sh $(NODES)"

else

.PHONY: integration
integration:
	$(error You need Docker to run gen_rpc integration tests)

endif

# =============================================================================
# Build targets
# =============================================================================

.PHONY: all
all: $(REBAR)
	@REBAR_PROFILE=dev $(REBAR) do compile

.PHONY: test
test: $(REBAR) epmd
	@REBAR_PROFILE=test $(REBAR) do ct -c, cover

.PHONY: dialyzer
dialyzer: $(REBAR) $(PLT_FILE)
	@REBAR_PROFILE=dev $(REBAR) do dialyzer

.PHONY: xref
xref: $(REBAR)
	@REBAR_PROFILE=dev $(REBAR) do xref

.PHONY: spec
spec: dialyzer
	@$(TYPER) --annotate-inc-files -I ./include --plt $(PLT_FILE) -r src/

.PHONY: dist
dist: $(REBAR) test
	@REBAR_PROFILE=dev $(REBAR) do dialyzer, xref

.PHONY: coveralls
coveralls:
	@REBAR_PROFILE=test $(REBAR) do coveralls send || true

.PHONY: travis
travis: testclean dist coveralls integration

# =============================================================================
# Run targets
# =============================================================================

.PHONY: shell
shell: shell-master

.PHONY: shell-master
shell-master: $(REBAR) epmd
	@REBAR_PROFILE=dev $(REBAR) do shell --name gen_rpc_master@127.0.0.1 --config test/gen_rpc.master.config

.PHONY: shell-slave
shell-slave: $(REBAR) epmd
	@REBAR_PROFILE=dev $(REBAR) do shell --name gen_rpc_slave@127.0.0.1 --config test/gen_rpc.slave.config

# =============================================================================
# Misc targets
# =============================================================================

.PHONY: clean
clean: $(REBAR)
	@$(REBAR) clean
	@rm -f rebar.lock

.PHONY: distclean
distclean: $(REBAR)
	@rm -rf _build/* _plt .rebar Mnesia* mnesia* log/ data/ temp-data/ rebar.lock
	@find . -name erl_crash.dump -type f -delete
	@$(REBAR) clean -a

.PHONY: testclean
testclean:
	@rm -fr _build/test && rm -rf ./test/*.beam
	@find log/ct -maxdepth 1 -name ct_run* -type d -cmin +360 -exec rm -fr {} \; 2> /dev/null || true

.PHONY: epmd
epmd:
	@pgrep epmd 2> /dev/null > /dev/null || epmd -daemon || true

.PHONY: tags
tags:
	find src _build/default/lib -name "*.[he]rl" -print | etags -

$(REBAR):
	@curl -Lo rebar3 $(REBAR_URL) || wget $(REBAR_URL)
	@chmod a+x rebar3
	@$(CURDIR)/rebar3 update

$(PLT_FILE):
	@REBAR_PROFILE=dev $(REBAR) do dialyzer || true
