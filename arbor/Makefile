.PHONY: help install venv requirements run clean

# Default target
help:
	@echo "ARBOR - Recursive Directory Upload Server"
	@echo ""
	@echo "Available targets:"
	@echo "  make install    - Install venv and requirements, then run server"
	@echo "  make venv       - Create virtual environment (if not exists)"
	@echo "  make requirements - Install Python dependencies"
	@echo "  make run        - Run the server"
	@echo "  make clean      - Remove virtual environment and build artifacts"
	@echo "  make test       - Run the test suite"

# Create virtual environment if it doesn't exist
venv:
	@if [ ! -d "venv" ]; then \
		echo "Creating virtual environment..."; \
		python3 -m venv venv; \
	else \
		echo "Virtual environment already exists."; \
	fi

# Install requirements
requirements: venv
	@echo "Installing requirements..."
	. venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt

# Run the server
run: venv
	@echo "Activating virtual environment and running ARBOR server..."
	. venv/bin/activate && python upload_server.py

# Install everything and run (default workflow)
install: venv requirements run

# Run tests
test: venv requirements
	@echo "Running tests..."
	. venv/bin/activate && python test_server.py

# Clean up
clean:
	@echo "Cleaning up..."
	rm -rf venv
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	@echo "Cleanup complete."
