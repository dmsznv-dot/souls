#!/bin/sh
# Runs every headless suite. A suite fails on a non-zero exit, on any SCRIPT ERROR line, or on
# any non-finite vector / quaternion warning (NaN), whatever its exit code says.
# Usage: tools/run_tests.sh [path-to-godot]
GODOT="${1:-godot}"
status=0
for suite in stage_one duel expedition weapons foes music ai weather poise dressing forest movement; do
	log=$("$GODOT" --headless --path . --script "res://tests/$suite.gd" 2>&1)
	code=$?
	echo "$log" | grep -E "checks passed|FAIL"
	if [ $code -ne 0 ] || echo "$log" | grep -qE "SCRIPT ERROR|NaN|not finite|must be normalized"; then
		echo "!! $suite failed (exit $code or script errors / NaN in the log)"
		status=1
	fi
done
exit $status
