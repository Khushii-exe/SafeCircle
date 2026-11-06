#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"

echo "=================================================="
echo " Running SafeCircle Web in Google Chrome on Mac M2"
echo "=================================================="

# Check if backend is running
if ! curl -s http://127.0.0.1:8000/health > /dev/null 2>&1; then
    echo "Starting backend dev server..."
    cd "$DIR/backend"
    source .venv/bin/activate
    SEED_DEMO=1 uvicorn app.main:app --host 0.0.0.0 --port 8000 &
    sleep 2
fi

echo "Starting Flutter web app in Chrome..."
cd "$DIR"
flutter run -d chrome --dart-define=API_BASE=https://safecircle-backend-dq8z.onrender.com
