.PHONY: help install venv requirements run clean test service-install service-uninstall service-start service-stop service-status service-logs

# Get the absolute path of this directory
ARBOR_DIR := $(shell pwd)
SYSTEMD_USER_DIR := $(HOME)/.config/systemd/user

# Default target
help:
	@echo "ARBOR - Recursive Directory Upload Server"
	@echo ""
	@echo "Available targets:"
	@echo "  make install         - Install venv and requirements, then run server"
	@echo "  make venv            - Create virtual environment (if not exists)"
	@echo "  make requirements    - Install Python dependencies"
	@echo "  make run             - Run the server (foreground)"
	@echo "  make clean           - Remove virtual environment and build artifacts"
	@echo "  make test            - Run the test suite"
	@echo ""
	@echo "Systemd Service (runs as user service):"
	@echo "  make service-install - Install and start systemd user service"
	@echo "  make service-uninstall - Stop and remove systemd user service"
	@echo "  make service-start   - Start the service"
	@echo "  make service-stop    - Stop the service"
	@echo "  make service-status  - Show service status"
	@echo "  make service-logs    - Follow service logs"

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

# ============================================================================
# Systemd User Service Management
# ============================================================================

# Install systemd user service
service-install: venv requirements
	@echo "Installing ARBOR systemd user service..."
	@mkdir -p $(SYSTEMD_USER_DIR)
	@sed 's|%h/arbor|$(ARBOR_DIR)|g' systemd/arbor.service > $(SYSTEMD_USER_DIR)/arbor.service
	@echo "Reloading systemd user daemon..."
	@systemctl --user daemon-reload
	@echo "Enabling ARBOR service to start on login..."
	@systemctl --user enable arbor.service
	@echo "Starting ARBOR service..."
	@systemctl --user start arbor.service
	@echo ""
	@echo "[OK] ARBOR service installed and started!"
	@echo ""
	@echo "Useful commands:"
	@echo "  make service-status  - Check status"
	@echo "  make service-logs    - View logs"
	@echo "  make service-stop    - Stop service"
	@echo ""
	@echo "To enable lingering (service runs even when not logged in):"
	@echo "  sudo loginctl enable-linger $(USER)"

# Uninstall systemd user service
service-uninstall:
	@echo "Stopping ARBOR service..."
	@-systemctl --user stop arbor.service 2>/dev/null || true
	@echo "Disabling ARBOR service..."
	@-systemctl --user disable arbor.service 2>/dev/null || true
	@echo "Removing service file..."
	@rm -f $(SYSTEMD_USER_DIR)/arbor.service
	@echo "Reloading systemd user daemon..."
	@systemctl --user daemon-reload
	@echo "[OK] ARBOR service uninstalled."

# Start the service
service-start:
	@systemctl --user start arbor.service
	@echo "[OK] ARBOR service started."

# Stop the service
service-stop:
	@systemctl --user stop arbor.service
	@echo "[OK] ARBOR service stopped."

# Show service status
service-status:
	@systemctl --user status arbor.service

# Follow service logs
service-logs:
	@journalctl --user -u arbor.service -f
