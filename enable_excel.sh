#!/bin/bash
echo "Setting up Excel export support..."

# Try different installation methods
echo "Method 1: Trying pipx..."
if command -v pipx &> /dev/null; then
    pipx install openpyxl
    echo "✅ Installed via pipx"
    exit 0
fi

echo "Method 2: Trying Homebrew..."
if command -v brew &> /dev/null; then
    brew install python-openpyxl 2>/dev/null && {
        echo "✅ Installed via Homebrew"
        exit 0
    }
fi

echo "Method 3: Creating virtual environment..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install openpyxl

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Virtual environment created with openpyxl"
    echo ""
    echo "Excel export will now work automatically!"
else
    echo "❌ Failed to install. Please try manually:"
    echo "  brew install pipx"
    echo "  pipx install openpyxl"
fi