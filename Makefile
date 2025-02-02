CWD ?= CURRENT_WORKING_DIRECTIONRY_NOT_SUPPLIED

# This flag is useful when running the consensus unit tests. It causes the test to wait up to the
# maximum delay specified in the source code and errors if additional unexpected messages are received.
# For example, if the test expects to receive 5 messages within 2 seconds:
# 	When EXTRA_MSG_FAIL = false: continue if 5 messages are received in 0.5 seconds
# 	When EXTRA_MSG_FAIL = true: wait for another 1.5 seconds after 5 messages are received in 0.5
#		                        seconds, and fail if any additional messages are received.
EXTRA_MSG_FAIL ?= false

# An easy way to turn off verbose test output for some of the test targets. For example
#  `$ make test_persistence` by default enables verbose testing
#  `VERBOSE_TEST="" make test_persistence` is an easy way to run the same tests without verbose output
VERBOSE_TEST ?= -v

.SILENT:

help:
	printf "Available targets\n\n"
	awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "%-30s %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

# Internal helper target - check if docker is installed
.PHONY: docker_check
docker_check:
	{ \
	if ( ! ( command -v docker >/dev/null && command -v docker-compose >/dev/null )); then \
		echo "Seems like you don't have Docker or docker-compose installed. Make sure you review docs/development/README.md before continuing"; \
		exit 1; \
	fi; \
	}

# Internal helper target - prompt the user before continuing
.PHONY: prompt_user
prompt_user:
	@echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]

.PHONY: go_vet
## Run `go vet` on all files in the current project
go_vet:
	go vet ./...

.PHONY: go_staticcheck
## Run `go staticcheck` on all files in the current project
go_staticcheck:
	{ \
	if command -v staticcheck >/dev/null; then \
		staticcheck ./...; \
	else \
		echo "Install with 'go install honnef.co/go/tools/cmd/staticcheck@latest'"; \
	fi; \
	}

.PHONY: go_doc
## Generate documentation for the current project using `godo`
go_doc:
	{ \
	if command -v godoc >/dev/null; then \
		echo "Visit http://localhost:6060/pocket"; \
		godoc -http=localhost:6060  -goroot=${PWD}/..; \
	else \
		echo "Install with 'go install golang.org/x/tools/cmd/godoc@latest'"; \
	fi; \
	}

.PHONY: go_clean_deps
## Runs `go mod tidy` && `go mod vendor`
go_clean_deps:
	go mod tidy && go mod vendor

.PHONY: build_and_watch
## Continous build Pocket's main entrypoint as files change
build_and_watch:
	/bin/sh ${PWD}/scripts/watch_build.sh

.PHONY: client_start
## Run a client daemon which is only used for debugging purposes
client_start: docker_check
	docker-compose -f build/deployments/docker-compose.yaml up -d client

.PHONY: client_connect
## Connect to the running client debugging daemon
client_connect: docker_check
	docker exec -it client /bin/bash -c "go run app/client/*.go"

# TODO(olshansky): Need to think of a Pocket related name for `compose_and_watch`, maybe just `pocket_watch`?
.PHONY: compose_and_watch
## Run a localnet composed of 4 consensus validators w/ hot reload & debugging
compose_and_watch: docker_check db_start
	docker-compose -f build/deployments/docker-compose.yaml up --force-recreate node1.consensus node2.consensus node3.consensus node4.consensus

.PHONY: db_start
## Start a detached local postgres and admin instance (this is auto-triggered by compose_and_watch)
db_start: docker_check
	docker-compose -f build/deployments/docker-compose.yaml up --no-recreate -d db pgadmin

.PHONY: db_cli
## Open a CLI to the local containerized postgres instance
db_cli:
	echo "View schema by running 'SELECT schema_name FROM information_schema.schemata;'"
	docker exec -it pocket-db bash -c "psql -U postgres"

.PHONY: db_drop
## Drop all schemas used for LocalNet development matching `node%`
db_drop: docker_check
	docker exec -it pocket-db bash -c "psql -U postgres -d postgres -a -f /tmp/scripts/drop_all_schemas.sql"

.PHONY: db_bench_init
## Initialize pgbench on local postgres - needs to be called once after container is created.
db_bench_init: docker_check
	docker exec -it pocket-db bash -c "pgbench -i -U postgres -d postgres"

.PHONY: db_bench
## Run a local benchmark against the local postgres instance - TODO(olshansky): visualize results
db_bench: docker_check
	docker exec -it pocket-db bash -c "pgbench -U postgres -d postgres"

.PHONY: db_admin
## Helper to access to postgres admin GUI interface
db_admin:
	echo "Open http://0.0.0.0:5050 and login with 'pgadmin4@pgadmin.org' and 'pgadmin4'.\n The password is 'postgres'"

.PHONY: docker_kill_all
## Kill all containers started by the docker-compose file
docker_kill_all: docker_check
	docker-compose -f build/deployments/docker-compose.yaml down

.PHONY: docker_wipe
## [WARNING] Remove all the docker containers, images and volumes.
docker_wipe: docker_check prompt_user
	docker ps -a -q | xargs -r -I {} docker stop {}
	docker ps -a -q | xargs -r -I {} docker rm {}
	docker images -q | xargs -r -I {} docker rmi {}
	docker volume ls -q | xargs -r -I {} docker volume rm {}

# Reference the following for mockgen with 1.18: https://github.com/golang/mock/issues/621

.PHONY: mockgen
## Use `mockgen` to generate mocks used for testing purposes of all the modules.
mockgen:
	$(eval modules_dir = "shared/modules")
	$(eval mocks_dir = "shared/modules/mocks")
	rm -rf ${mocks_dir}
	mockgen --source=${modules_dir}/persistence_module.go -destination=${mocks_dir}/persistence_module_mock.go -aux_files=github.com/pokt-network/pocket/${modules_dir}=${modules_dir}/module.go
	mockgen --source=${modules_dir}/p2p_module.go -destination=${mocks_dir}/p2p_module_mock.go -aux_files=github.com/pokt-network/pocket/${modules_dir}=${modules_dir}/module.go
	mockgen --source=${modules_dir}/utility_module.go -destination=${mocks_dir}/utility_module_mock.go -aux_files=github.com/pokt-network/pocket/${modules_dir}=${modules_dir}/module.go
	mockgen --source=${modules_dir}/consensus_module.go -destination=${mocks_dir}/consensus_module_mock.go -aux_files=github.com/pokt-network/pocket/${modules_dir}=${modules_dir}/module.go
	mockgen --source=${modules_dir}/bus_module.go -destination=${mocks_dir}/bus_module_mock.go -aux_files=github.com/pokt-network/pocket/${modules_dir}=${modules_dir}/module.go
	echo "Mocks generated in ${modules_dir}/mocks"

	$(eval p2p_types_dir = "p2p/types")
	$(eval p2p_type_mocks_dir = "p2p/types/mocks")
	rm -rf ${p2p_type_mocks_dir}
	mockgen --source=${p2p_types_dir}/network.go -destination=${p2p_type_mocks_dir}/network_mock.go
	echo "P2P mocks generated in ${p2p_types_dir}/mocks"

.PHONY: test_all
## Run all go unit tests
test_all: # generate_mocks
	go test -p=1 -count=1 ./...

.PHONY: test_race
## Identify all unit tests that may result in race conditions
test_race: # generate_mocks
	go test -race ./...

.PHONY: test_utility_module
## Run all go utility module unit tests
test_utility_module: # generate_mocks
	go test ${VERBOSE_TEST} ./shared/tests/utility_module/...

.PHONY: test_utility_types
## Run all go utility types module unit tests
test_utility_types: # generate_mocks
	go test ${VERBOSE_TEST} ./utility/types/...

.PHONY: test_shared
## Run all go unit tests in the shared module
test_shared: # generate_mocks
	go test ./shared/...

.PHONY: test_consensus
## Run all go unit tests in the Consensus module
test_consensus: # mockgen
	go test ${VERBOSE_TEST} ./consensus/...

.PHONY: test_pre_persistence
## Run all go per persistence unit tests
test_pre_persistence: # generate_mocks
	go test ./persistence/pre_persistence/...

.PHONY: test_hotstuff
## Run all go unit tests related to hotstuff consensus
test_hotstuff: # mockgen
	go test ${VERBOSE_TEST} ./consensus/consensus_tests -run Hotstuff -failOnExtraMessages=${EXTRA_MSG_FAIL}

.PHONY: test_pacemaker
## Run all go unit tests related to the hotstuff pacemaker
test_pacemaker: # mockgen
	go test ${VERBOSE_TEST} ./consensus/consensus_tests -run Pacemaker -failOnExtraMessages=${EXTRA_MSG_FAIL}

.PHONY: test_vrf
## Run all go unit tests in the VRF library
test_vrf:
	go test ${VERBOSE_TEST} ./consensus/leader_election/vrf

.PHONY: test_sortition
## Run all go unit tests in the Sortition library
test_sortition:
	go test ${VERBOSE_TEST} ./consensus/leader_election/sortition

.PHONY: test_persistence
## Run all go unit tests in the Persistence module
test_persistence:
	go test ${VERBOSE_TEST} -p=1 ./persistence/...

.PHONY: benchmark_sortition
## Benchmark the Sortition library
benchmark_sortition:
	go test ${VERBOSE_TEST} ./consensus/leader_election/sortition -bench=.

# TODO(team): Tested locally with `protoc` version `libprotoc 3.19.4`. In the near future, only the Dockerfiles will be used to compile protos.

.PHONY: protogen_show
## A simple `find` command that shows you the generated protobufs.
protogen_show:
	find . -name "*.pb.go" | grep -v -e "prototype" -e "vendor"

.PHONY: protogen_clean
## Remove all the generated protobufs.
protogen_clean:
	find . -name "*.pb.go" | grep -v -e "prototype" -e "vendor" | xargs -r rm

.PHONY: protogen_local
## Generate go structures for all of the protobufs
protogen_local:
	$(eval proto_dir = "./shared/types/proto/")
	protoc --go_opt=paths=source_relative -I=${proto_dir} -I=./shared/types/proto             --go_out=./shared/types         ./shared/types/proto/*.proto         --experimental_allow_proto3_optional
	protoc --go_opt=paths=source_relative -I=${proto_dir} -I=./utility/proto                  --go_out=./utility/types        ./utility/proto/*.proto              --experimental_allow_proto3_optional
	protoc --go_opt=paths=source_relative -I=${proto_dir} -I=./shared/types/genesis/proto     --go_out=./shared/types/genesis ./shared/types/genesis/proto/*.proto --experimental_allow_proto3_optional
	protoc --go_opt=paths=source_relative -I=${proto_dir} -I=./consensus/types/proto          --go_out=./consensus/types      ./consensus/types/proto/*.proto      --experimental_allow_proto3_optional
	protoc --go_opt=paths=source_relative -I=${proto_dir} -I=./p2p/raintree/types/proto       --go_out=./p2p/types            ./p2p/raintree/types/proto/*.proto   --experimental_allow_proto3_optional

	echo "View generated proto files by running: make protogen_show"

.PHONY: protogen_docker_m1
## TODO(derrandz): Test, validate & update.
protogen_docker_m1: docker_check
	docker build  -t pocket/proto-generator -f ./build/Dockerfile.m1.proto . && docker run --platform=linux/amd64 -it -v $(CWD)/shared:/usr/src/app/shared pocket/proto-generator

.PHONY: protogen_docker
## TODO(derrandz): Test, validate & update.
protogen_docker: docker_check
	docker build -t pocket/proto-generator -f ./build/Dockerfile.proto . && docker run -it pocket/proto-generator

.PHONY: gofmt
## Format all the .go files in the project in place.
gofmt:
	gofmt -w -s .

## Module commands

.PNONY: test_p2p_wire_codec
## Run the p2p wire codec behavior test
test_p2p_wire_codec:
	go test -run TestWireCodec -v -race ./p2p

.PHONY: test_p2p_socket
## Run the p2p net IO behaviors test
test_p2p_socket:
	go test -run TestSocket -v -race ./p2p

.PHONY: test_p2p_types
## Run p2p subcomponents' tests
test_p2p_types:
	go test ${VERBOSE_TEST} -race ./p2p/types

.PHONY: test_p2p
## Run all p2p
test_p2p:
	go test ${VERBOSE_TEST} -count=1 ./p2p/...

.PHONY: test_p2p_addrbook
## Run all P2P addr book related tests
test_p2p_addrbook:
	go test -run AddrBook -v -count=1 ./p2p/...

.PHONY: benchmark_p2p_addrbook
## Benchmark all P2P addr book related tests
benchmark_p2p_addrbook:
	go test -bench=. -run BenchmarkAddrBook -v -count=1 ./p2p/...

### Inspired by @goldinguy_ in this post: https://goldin.io/blog/stop-using-todo ###
# TODO          - General Purpose catch-all.
# TECHDEBT      - Not a great implementation, but we need to fix it later.
# IMPROVE       - A nice to have, but not a priority. It's okay if we never get to this.
# DISCUSS       - Probably requires a lengthy offline discussion to understand next steps.
# INCOMPLETE    - A change which was out of scope of a specific PR but needed to be documented.
# INVESTIGATE   - TBD what was going on, but needed to continue moving and not get distracted.
# CLEANUP       - Like TECHDEBT, but not as bad.  It's okay if we never get to this.
# HACK          - Like TECHDEBT, but much worse. This needs to be prioritized
# REFACTOR      - Similar to TECHDEBT, but will require a substantial rewrite and change across the codebase
# CONSIDERATION - A comment that involves extra work but was thoughts / considered as part of some implementation
# INTHISCOMMIT  - SHOULD NEVER BE COMMITTED TO MASTER. It is a way for the review of a PR to start / reply to a discussion.
TODO_KEYWORDS = -e "TODO" -e "TECHDEBT" -e "IMPROVE" -e "DISCUSS" -e "INCOMPLETE" -e "INVESTIGATE" -e "CLEANUP" -e "HACK" -e "REFACTOR" -e "CONSIDERATION" -e "INTHISCOMMIT"

.PHONY: todo_list
## List all the TODOs in the project (excludes vendor and prototype directories)
todo_list:
	grep --exclude-dir={.git,vendor,prototype} -r ${TODO_KEYWORDS}  .

.PHONY: todo_count
## Print a count of all the TODOs in the project
todo_count:
	grep --exclude-dir={.git,vendor,prototype} -r ${TODO_KEYWORDS} . | wc -l

.PHONY: develop_and_test
## Run all of the make commands necessary to develop on the project and verify the tests pass
develop_test:
		make mockgen && \
		make protogen_clean && make protogen_local && \
		make go_clean_deps && \
		make test_all
