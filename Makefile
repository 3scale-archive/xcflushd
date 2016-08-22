MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_PATH := $(patsubst %/,%,$(dir $(MKFILE_PATH)))

default: test

build:
	docker build -t xcflushd $(PROJECT_PATH)

test: build
	docker run -t xcflushd

bash: build
	docker run -t -i xcflushd /bin/bash
