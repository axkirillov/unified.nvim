all: test

.PHONY: test
test:
	@echo "Running tests..."
	@./test/run_tests.sh

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@find . -name "*.swp" -delete
	@find . -name "*.swo" -delete