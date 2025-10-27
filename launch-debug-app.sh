#!/bin/bash
cd "$(dirname "$0")"

if [ ! -d ".debug/AeroSporkApp.app" ]; then
    echo "❌ Debug .app not found. Building first..."
    ./build-debug-app.sh
fi

echo ""
echo "🚀 Launching AeroSpork Debug .app..."
echo ""
echo "📊 To view logs, open Console.app and filter by:"
echo "   • Subsystem: com.wbs.aerospork.debug"
echo "   • Process: AeroSporkApp"
echo ""

open .debug/AeroSporkApp.app
