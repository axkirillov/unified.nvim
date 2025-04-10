.PHONY: tests
tests:
	@echo "Running tests..."
	@./test/run_tests.sh $(TEST_ARGS)

.PHONY: test
test:
	@echo "Running single test: $(TEST)"
	@./test/run_tests.sh --test=$(TEST)

.PHONY: lint
lint:
	@echo "Linting..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim --check lua/ plugin/ test/ example/

.PHONY: format
format:
	@echo "Formatting..."
	@docker run --rm -v $(CURDIR):/app stylua-nvim lua/ plugin/ test/ example/

.PHONY: docker-build
docker-build:
	@echo "Building Docker image..."
	@docker build -t stylua-nvim .

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@find . -name "*.swp" -delete
	@find . -name "*.swo" -delete
