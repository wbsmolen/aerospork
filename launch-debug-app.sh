#!/bin/bash
cd "$(dirname "$0")"

if [ ! -d ".debug/AeroSpork-Debug.app" ]; then
    echo "❌ Debug .app not found. Building first..."
    ./build-debug-app.sh
fi

echo ""
echo "🚀 Launching AeroSpork Debug .app..."
echo ""
echo "📊 To view logs:"
echo "   log stream --debug --predicate 'subsystem == \"com.wbs.aerospork.debug\"'"
echo "   (In Console.app, filter by subsystem com.wbs.aerospork.debug and turn on"
echo "    Action > Include Debug Messages, or the AEROSPORK_DEBUG_LOG trace is hidden.)"
echo ""

open .debug/AeroSpork-Debug.app
