all: setup build test lint

.PHONY: setup
setup:
	stack setup $(STACK_ARGUMENTS)
	stack build $(STACK_ARGUMENTS) --dependencies-only --test --no-run-tests
	stack install $(STACK_ARGUMENTS) --copy-compiler-tool hlint weeder

.PHONY: build
build:
	stack build $(STACK_ARGUMENTS) --fast --pedantic --test --no-run-tests

.PHONY: test
test:
	stack build $(STACK_ARGUMENTS) --fast --pedantic --test

.PHONY: lint
lint:
	stack exec $(STACK_ARGUMENTS) hlint library
	stack exec $(STACK_ARGUMENTS) weeder .

.PHONY: clean
clean:
	stack clean

.PHONY: check-nightly
check-nightly: STACK_ARGUMENTS=--stack-yaml stack-nightly.yaml --resolver nightly
check-nightly: setup build test
