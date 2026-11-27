#!/bin/bash
# usage: tool_shots.sh before|after   (run from apps/mobile)
out="$(cd ../.. && pwd)/review/app"
for w in 390 1024; do for t in light dark; do
  flutter test test/screenshots/q_app_test.dart --dart-define=SCREENSHOTS="$out" --dart-define=SHOT_PHASE="$1" --dart-define=SHOT_WIDTH=$w --dart-define=SHOT_THEME=$t 2>&1 | tail -30
done; done
