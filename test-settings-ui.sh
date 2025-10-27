#!/bin/bash
# Test script for AeroSpork Settings UI

set -e

CONFIG_FILE="$HOME/.aerospork-debug.toml"
BACKUP_FILE="${CONFIG_FILE}.test-backup"

echo "================================================"
echo "AeroSpork Settings UI Test Suite"
echo "================================================"
echo ""

# Backup existing config
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing config to $BACKUP_FILE"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

# Test 1: Keybinding Preservation (CRITICAL)
echo "Test 1: Keybinding Preservation"
echo "--------------------------------"
cat > "$CONFIG_FILE" << 'EOF'
# Test config with keybindings
start-at-login = false

[mode.main.binding]
cmd-h = "focus left"
cmd-j = "focus down"
cmd-k = "focus up"
cmd-l = "focus right"
cmd-1 = "workspace 1"
cmd-2 = "workspace 2"

[gaps]
inner.horizontal = 5
inner.vertical = 5
outer.left = 10
outer.right = 10
outer.top = 10
outer.bottom = 10
EOF

echo "Created test config with 6 keybindings and gaps"
echo ""
echo "MANUAL STEPS:"
echo "1. Run: ./run-debug.sh"
echo "2. Open Settings UI from menu bar"
echo "3. Go to Gaps tab"
echo "4. Change inner gaps from 5 to 15"
echo "5. Click Save"
echo "6. Close settings and app"
echo "7. Run this script again to verify"
echo ""
echo "Press Enter when ready to continue (after completing above steps)..."
read

# Verify keybindings still present
echo "Verifying config file..."
if grep -q "cmd-h.*focus left" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-h' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-h' LOST!"
    exit 1
fi

if grep -q "cmd-j.*focus down" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-j' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-j' LOST!"
    exit 1
fi

if grep -q "cmd-k.*focus up" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-k' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-k' LOST!"
    exit 1
fi

if grep -q "cmd-l.*focus right" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-l' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-l' LOST!"
    exit 1
fi

if grep -q "cmd-1.*workspace 1" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-1' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-1' LOST!"
    exit 1
fi

if grep -q "cmd-2.*workspace 2" "$CONFIG_FILE"; then
    echo "✓ Keybinding 'cmd-2' preserved"
else
    echo "✗ FAIL: Keybinding 'cmd-2' LOST!"
    exit 1
fi

# Verify gaps were updated
if grep -q "inner.*horizontal.*=.*15" "$CONFIG_FILE" || grep -q "horizontal.*=.*15" "$CONFIG_FILE"; then
    echo "✓ Inner gaps updated to 15"
else
    echo "✗ FAIL: Inner gaps NOT updated!"
    exit 1
fi

echo ""
echo "✓✓✓ Test 1 PASSED: All keybindings preserved!"
echo ""

# Test 2: Horizontal/Vertical Gap Handling
echo "Test 2: Horizontal/Vertical Gap Handling"
echo "-----------------------------------------"
cat > "$CONFIG_FILE" << 'EOF'
[gaps]
inner.horizontal = 10
inner.vertical = 20
EOF

echo "Created config with different H/V gaps (10 vs 20)"
echo ""
echo "MANUAL STEPS:"
echo "1. Run: ./run-debug.sh"
echo "2. Open Settings UI"
echo "3. Go to Gaps tab"
echo "4. Note the inner gaps value (should be 10)"
echo "5. Check console for warning about H/V mismatch"
echo "6. Click Save (without changing anything)"
echo "7. Close app"
echo "8. Press Enter to verify"
echo ""
read

# Verify both are now the same
h_gap=$(grep "inner.*horizontal" "$CONFIG_FILE" | grep -o '[0-9]\+' || echo "0")
v_gap=$(grep "inner.*vertical" "$CONFIG_FILE" | grep -o '[0-9]\+' || echo "0")

if [ "$h_gap" == "$v_gap" ]; then
    echo "✓ Horizontal and vertical gaps unified (both = $h_gap)"
else
    echo "✗ FAIL: H/V gaps still differ ($h_gap vs $v_gap)"
    exit 1
fi

echo ""
echo "✓✓✓ Test 2 PASSED!"
echo ""

# Test 3: Workspace Name Generation
echo "Test 3: Workspace Name Generation"
echo "----------------------------------"
cat > "$CONFIG_FILE" << 'EOF'
[mode.main.binding]
cmd-1 = "workspace 1"
cmd-2 = "workspace 2"
cmd-3 = "workspace 3"
EOF

echo "Created config with workspaces 1, 2, 3 in keybindings"
echo ""
echo "MANUAL STEPS:"
echo "1. Run: ./run-debug.sh"
echo "2. Open Settings UI"
echo "3. Go to Workspaces & Monitors tab"
echo "4. Click the '+' button to add a workspace assignment"
echo "5. Verify the new workspace name is '4' (not 1, 2, or 3)"
echo "6. Close without saving"
echo ""
echo "This test is MANUAL - did it work correctly? (y/n)"
read -r answer
if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
    echo "✓✓✓ Test 3 PASSED (manual verification)"
else
    echo "✗ Test 3 FAILED"
    exit 1
fi

echo ""

# Cleanup
if [ -f "$BACKUP_FILE" ]; then
    echo "Restoring original config from backup"
    mv "$BACKUP_FILE" "$CONFIG_FILE"
fi

echo "================================================"
echo "All Tests Complete!"
echo "================================================"
echo ""
echo "Summary:"
echo "✓ Test 1: Keybinding preservation"
echo "✓ Test 2: H/V gap handling"
echo "✓ Test 3: Workspace name generation"
echo ""
echo "Settings UI is working correctly!"
