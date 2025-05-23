.PHONY: tests
tests:
	@./test/run_tests.sh $(TEST_ARGS)

.PHONY: test
test:
	@./test/run_tests.sh --test=$(TEST)

.PHONY: lint
lint: docker-build
	@echo "Linting..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim --check lua/ test/ example/

.PHONY: format
format: docker-build
	@echo "Formatting..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim lua/ test/ example/

.PHONY: docker-build
docker-build:
	@echo "Building Docker image..."
	@docker build -t stylua-nvim .

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@find . -name "*.swp" -delete
	@find . -name "*.swo" -delete
