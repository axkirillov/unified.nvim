.PHONY: tests
tests:
	@./test/run_tests.sh $(TEST_ARGS)

.PHONY: test
test:
	@./test/run_tests.sh --test=$(TEST)

# Formatting uses stylua. By default we run the version pinned by the Nix flake
# (no local install needed). If you don't have Nix, the *-docker targets run the
# same stylua inside a container instead (see Dockerfile).
.PHONY: lint
lint:
	@echo "Linting (nix)..."
	@nix run .#stylua -- --check lua/ test/ example/

.PHONY: format
format:
	@echo "Formatting (nix)..."
	@nix run .#stylua -- lua/ test/ example/

.PHONY: docker-build
docker-build:
	@echo "Building Docker image..."
	@docker build -t stylua-nvim .

.PHONY: lint-docker
lint-docker: docker-build
	@echo "Linting (docker)..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim --check lua/ test/ example/

.PHONY: format-docker
format-docker: docker-build
	@echo "Formatting (docker)..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim lua/ test/ example/

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@find . -name "*.swp" -delete
	@find . -name "*.swo" -delete
