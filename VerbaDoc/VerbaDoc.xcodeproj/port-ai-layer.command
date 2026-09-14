#!/bin/bash
# ================================================================
#  STALE DUPLICATE - DO NOT RUN THIS FILE.
#
#  This is an out-of-date copy of the VerbaDoc AI-layer installer. It
#  was created by mistake inside a stray `VerbaDoc.xcodeproj/` directory
#  (that directory is not a real Xcode project - it holds only this
#  file).
#
#  This copy LACKS the safety gates the real one has:
#    - it wires the Tutor tab even if the tutor screen failed to install
#    - it has no mixed-version warning for skipped AI-layer files
#    - it copies Config.xcconfig BEFORE creating .gitignore
#    - it checks fewer collision-prone symbol names
#
#  Run the real one instead:
#      bash ~/Desktop/VerbaDoc/VerbaDoc/port-ai-layer.command
#
#  Then delete this stray directory:
#      rm -rf ~/Desktop/VerbaDoc/VerbaDoc/VerbaDoc.xcodeproj
# ================================================================

echo "STALE COPY - not running."
echo ""
echo "Use the real installer instead:"
echo "  bash ~/Desktop/VerbaDoc/VerbaDoc/port-ai-layer.command"
echo ""
echo "Then delete this stray directory (it is NOT an Xcode project):"
echo "  rm -rf ~/Desktop/VerbaDoc/VerbaDoc/VerbaDoc.xcodeproj"
exit 1
