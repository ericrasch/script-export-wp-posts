#!/bin/bash
echo "=== Setting up Excel Export Support ==="
echo ""
echo "This script installs openpyxl for Excel generation."
echo ""

# Detect Python command
PYTHON_CMD=""
for cmd in python3 /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if command -v $cmd &> /dev/null; then
        PYTHON_CMD=$cmd
        break
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Python 3 is not installed."
    echo "Please install Python 3 first (e.g., brew install python@3)"
    exit 1
fi

echo "Using Python: $PYTHON_CMD"

# Check if openpyxl is already installed
if $PYTHON_CMD -c "import openpyxl" 2>/dev/null; then
    echo "✅ openpyxl is already installed!"
    echo ""
    echo "Excel export is ready to use."
    exit 0
fi

# Install openpyxl with --user and --break-system-packages flags
echo "Installing openpyxl for current user..."
echo "(This will not affect your system Python installation)"
echo ""

if $PYTHON_CMD -m pip install --user --break-system-packages openpyxl 2>/dev/null || \
   $PYTHON_CMD -m pip install --user openpyxl 2>/dev/null; then
    echo "✅ openpyxl installed successfully!"
    echo ""
    echo "✅ Excel export support is now enabled!"
    echo "The package was installed in your user directory: ~/.local/"
    echo ""
    echo "You can now run the export script and Excel files will be generated."
else
    echo "❌ Failed to install openpyxl"
    echo ""
    echo "Alternative: Create a virtual environment:"
    echo "1. python3 -m venv ~/excel_env"
    echo "2. source ~/excel_env/bin/activate"
    echo "3. pip install openpyxl"
    echo ""
    echo "Then run the export script while the virtual environment is active."
    exit 1
fi