BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
IMAGE := jecklgamis/postgres:$(BRANCH)
POSTGRES_PASSWORD ?= changeme

default:
	cat ./Makefile
image:
	docker build -t $(IMAGE) .
run:
	docker run -p 5432:5432 -e POSTGRES_PASSWORD=$(POSTGRES_PASSWORD) $(IMAGE)
run-bash:
	docker run -i -t $(IMAGE) /bin/bash
up: image run
