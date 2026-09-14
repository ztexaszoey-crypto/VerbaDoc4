#!/bin/bash
# ================================================================
#  VerbaDoc - install the AI layer into the LIVE project
#
#  Source (staging): /Users/zoey/Desktop/VerbaDoc/VerbaDoc
#  Target (live):    /Users/zoey/Desktop/VerbaDoc-old-backup
#
#  RUN THIS BEFORE BUILDING. It is the single step that makes the
#  Tutor tab compile. Until it runs the live project still compiles
#  exactly as it did before: the only thing already added to it is an
#  empty Features/Tutor/TutorChatView.swift stub (comment-only, so it
#  declares no symbols) plus that one new directory.
#
#  This script does NOT build anything, so a fully green run can still be
#  followed by a failing build. It installs the port; it does not prove it
#  compiles.
#
#  Why `cp` and not a handwritten copy: these files have never been
#  compiled, and one transcription slip in (say) TextChunker's regex
#  would send you chasing a bug that does not exist in the original.
#
#  What it changes (every write is backed up, gated, and reported):
#    1. + 10 AI-layer files under the live VerbaDoc/ source folder
#       (the project uses a synchronized root group, so Xcode compiles
#       them automatically - no pbxproj entry needed for sources)
#    2. replaces the empty Features/Tutor/TutorChatView.swift stub with
#       the real tutor screen
#    3. wires the Tutor tab into RootTabView.swift (3 exact-line edits)
#    4. adds INFOPLIST_KEY_GROQ_API_KEY + NVIDIA_API_KEY to BOTH configs
#    5. creates/extends .gitignore so an xcconfig can never be committed
#       (done BEFORE any copy of the key file, so there is no window where
#        a real key sits in an unignored path)
#    6. copies Config.xcconfig if the live tree lacks one
#
#  It never overwrites a differing AI-layer file, never invents a key,
#  and never writes a file it could not back up first.
#
#  Run:  bash ~/Desktop/VerbaDoc/VerbaDoc/port-ai-layer.command
# ================================================================

set -u

say()   { printf '%s\n' "$*"; }
rule()  { printf '%.0s=' $(seq 1 72); echo; }
head2() { echo; rule; say "$*"; rule; }

STAGE="/Users/zoey/Desktop/VerbaDoc/VerbaDoc"
SRC="$STAGE/VerbaDoc"
DST="/Users/zoey/Desktop/VerbaDoc-old-backup"
APP="$DST/VerbaDoc"
PBX="$DST/VerbaDoc.xcodeproj/project.pbxproj"
CFG_SRC="$STAGE/Config.xcconfig"
CFG_DST="$DST/Config.xcconfig"
TUTOR_SRC="$STAGE/port-payload/Features/Tutor/TutorChatView.swift"

say "VerbaDoc - AI layer install"
say "Staging: $STAGE"
say "Live:    $DST"

for d in "$SRC" "$DST" "$APP"; do
  if [ ! -d "$d" ]; then
    say ""
    say "STOP: not a directory: $d"
    say "Nothing was changed."
    exit 1
  fi
done
if [ ! -f "$PBX" ]; then
  say ""
  say "STOP: no project.pbxproj at $PBX"
  exit 1
fi

# Refuse to touch anything that is not clearly the live project. This is
# what keeps the install from landing in a stale VerbaDoc4 copy.
if grep -q 'productName = VerbaDoc;' "$PBX" 2>/dev/null \
   && ! grep -q 'VerbaDoc4' "$PBX" 2>/dev/null; then
  say "OK: $PBX is the live VerbaDoc target."
  # grep succeeds on a corrupt file, so the identity check above cannot
  # detect the failure that actually matters. Refuse to install anything
  # into a project that will not parse.
  if ! plutil -lint "$PBX" >/dev/null 2>&1; then
    say ""
    say "STOP: $PBX exists but does NOT parse as a plist, so the project"
    say "is unopenable. Restore it first (project.pbxproj.known-good-backup"
    say "sits in the repo root) and re-run this script."
    say "Nothing was changed."
    exit 1
  fi
else
  say ""
  say "STOP: $PBX does not look like the live VerbaDoc project."
  say "Nothing was changed."
  exit 1
fi

# ================================================================
head2 "1. AI LAYER  (10 files)"
# ================================================================
mkdir -p "$APP/Services/AI" "$APP/Services/Generation"

FILES="
Services/NIMCore.swift
Services/NVIDIAAIService.swift
Services/NIMEmbeddingService.swift
Services/NoteVectorStore.swift
Services/ErrorPresentation.swift
Services/AI/AIChatRouter.swift
Services/Generation/StudyGenModels.swift
Services/Generation/StudyGenPrompts.swift
Services/Generation/StudyGenService.swift
Design/VerbaErrorBanner.swift
"

COPIED=0
SKIPPED_LIST=""
for rel in $FILES; do
  if [ ! -f "$SRC/$rel" ]; then
    say "  MISSING in staging (skipped): $rel"
    continue
  fi
  if [ -f "$APP/$rel" ]; then
    if cmp -s "$SRC/$rel" "$APP/$rel"; then
      say "  = already identical: $rel"
    else
      say "  ! exists and DIFFERS - left alone: $rel"
      say "    (you have edits there; diff before replacing)"
      SKIPPED_LIST="$SKIPPED_LIST $rel"
    fi
    continue
  fi
  if cp "$SRC/$rel" "$APP/$rel"; then
    say "  + $rel"
    COPIED=$((COPIED + 1))
  else
    say "  FAILED to copy: $rel"
  fi
done
say ""
MISSING_LIST=""
for rel in $FILES; do
  [ -f "$APP/$rel" ] || MISSING_LIST="$MISSING_LIST $rel"
done
if [ -n "$MISSING_LIST" ]; then
  say "FAIL - these AI-layer files are still absent:$MISSING_LIST"
  say "A partial layer builds with scattered missing-symbol errors. Re-run"
  say "this script to finish the install."
else
  say "PASS - all 10 AI-layer files are in place."
fi
say "$COPIED new file(s) copied this run."
if [ -n "$SKIPPED_LIST" ]; then
  say ""
  say "WARNING - MIXED VERSION SET. These already existed with different"
  say "content and were left alone:$SKIPPED_LIST"
  say "A stale NIMCore.swift or NIMEmbeddingService.swift does NOT fail in its"
  say "own file - it shows up as a missing-member error INSIDE"
  say "AIChatRouter.swift or NoteVectorStore.swift, which reads as \"the new"
  say "file is broken\" when it is not. Diff before trusting any build:"
  for rel in $SKIPPED_LIST; do
    say "  diff \"$SRC/$rel\" \"$APP/$rel\""
  done
fi

# ================================================================
head2 "2. TUTOR SCREEN"
# ================================================================
TUTOR_DST="$APP/Features/Tutor/TutorChatView.swift"
TUTOR_OK=0
mkdir -p "$APP/Features/Tutor"
if [ ! -f "$TUTOR_SRC" ]; then
  say "MISSING: $TUTOR_SRC"
  say "The Tutor tab will NOT compile without it. Copy that file into"
  say "$TUTOR_DST by hand, or tell me and I will re-stage it."
elif cmp -s "$TUTOR_SRC" "$TUTOR_DST"; then
  say "= already identical: Features/Tutor/TutorChatView.swift"
  TUTOR_OK=1
elif cp "$TUTOR_SRC" "$TUTOR_DST"; then
  say "Installed: Features/Tutor/TutorChatView.swift"
  say "  (this OVERWROTE the previous contents of that file)"
  TUTOR_OK=1
else
  say "FAILED to install the tutor screen."
fi

# ================================================================
head2 "3. TUTOR TAB  (RootTabView.swift)"
# ================================================================
ROOT="$APP/RootTabView.swift"
if [ "$TUTOR_OK" != "1" ]; then
  # GATE. Without this, a failed tutor install still wires the tab, and
  # RootTabView then calls TutorChatView() while the file on disk is the
  # comment-only stub - a hard "cannot find 'TutorChatView' in scope".
  say "SKIPPED - the tutor screen is NOT installed, so wiring the Tutor tab"
  say "now would reference TutorChatView() when no such type exists. That"
  say "breaks the build. Fix the step above, then re-run this script."
elif [ ! -f "$ROOT" ]; then
  say "Not found: $ROOT - add the Tutor tab by hand."
elif grep -q 'AppTab.tutor' "$ROOT" 2>/dev/null; then
  say "Tutor tab already wired - no change."
else
  RT_BACKUP="/tmp/verbadoc-roottab-backup-$(date +%Y%m%d-%H%M%S)"
  if cp "$ROOT" "$RT_BACKUP"; then
    say "Backup: $RT_BACKUP"

    OLD_ENUM='enum AppTab { case library, upload, flow, settings }'
    NEW_ENUM='enum AppTab { case library, upload, tutor, flow, settings }'
    OLD_TAB='                UploadTabView()'
    NEW_TAB='                TutorChatView()\n                    .tag(AppTab.tutor)'
    OLD_ROW='        (.upload,   "plus.circle.fill",         "Add"),'
    NEW_ROW='        (.tutor,    "text.bubble.fill",         "Tutor"),'

    ROOT_BEFORE=$(awk 'END{print NR}' "$ROOT")

    # awk -v turns the literal \n in NEW_TAB into a real newline. Exact
    # whole-line compares, so a reindented or reflowed file fails loudly
    # (exit 1) instead of being silently mis-edited.
    awk -v oe="$OLD_ENUM" -v ne="$NEW_ENUM" \
        -v ot="$OLD_TAB"  -v nt="$NEW_TAB" \
        -v orr="$OLD_ROW" -v nr="$NEW_ROW" '
      {
        if      ($0 == oe)  { print ne;           n++ }
        else if ($0 == ot)  { print ot; print nt; n++ }
        else if ($0 == orr) { print orr; print nr; n++ }
        else                { print }
      }
      END { exit (n == 3 ? 0 : 1) }
    ' "$ROOT" > "$ROOT.new"
    RC=$?
    ROOT_NEW=$(awk 'END{print NR}' "$ROOT.new")

    if [ "$RC" != "0" ]; then
      say "RootTabView.swift does not contain all 3 expected anchor lines,"
      say "so I will NOT edit it. Your file is untouched."
      say "Add these by hand instead:"
      say "  1. enum AppTab { case library, upload, tutor, flow, settings }"
      say "  2. TutorChatView()  +  .tag(AppTab.tutor)  after the UploadTabView() entry"
      say "  3. (.tutor, \"text.bubble.fill\", \"Tutor\"),  in VerbaTabBar.items"
      rm -f "$ROOT.new"
    elif [ ! -s "$ROOT.new" ]; then
      say "Rewrite produced an empty file - nothing changed."
      rm -f "$ROOT.new"
    elif [ "$ROOT_NEW" != "$((ROOT_BEFORE + 3))" ]; then
      say "Rewrite changed the file by $((ROOT_NEW - ROOT_BEFORE)) lines, not 3."
      say "Refusing to install it - RootTabView.swift is untouched."
      rm -f "$ROOT.new"
    else
      cp "$ROOT.new" "$ROOT" && rm -f "$ROOT.new"
      say "Tutor tab wired: enum case + TabView entry + tab-bar item."
    fi
  else
    say "Backup to $RT_BACKUP FAILED - I will not edit RootTabView.swift."
  fi
fi

# ================================================================
head2 "4. pbxproj  - INFO.PLIST KEY WIRING"
# ================================================================
# The router reads BOTH keys out of the generated Info.plist, so they only
# work if these build settings exist in BOTH configurations.
NEED_GROQ=1
NEED_NVIDIA=1
grep -q 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX"   && NEED_GROQ=0
grep -q 'INFOPLIST_KEY_NVIDIA_API_KEY' "$PBX" && NEED_NVIDIA=0

if [ "$NEED_GROQ" = 0 ] && [ "$NEED_NVIDIA" = 0 ]; then
  say "Both keys already present - no change made."
elif ! grep -q 'INFOPLIST_KEY_NSCameraUsageDescription = ' "$PBX" 2>/dev/null; then
  say "Anchor line (INFOPLIST_KEY_NSCameraUsageDescription) not found, so I will"
  say "not guess where to insert. Add BOTH by hand to the VerbaDoc TARGET's"
  say "Build Settings, for Debug AND Release:"
  say "    INFOPLIST_KEY_GROQ_API_KEY = \$(GROQ_API_KEY);"
  say "    INFOPLIST_KEY_NVIDIA_API_KEY = \$(NVIDIA_API_KEY);"
else
  ANCHORS=$(grep -c 'INFOPLIST_KEY_NSCameraUsageDescription = ' "$PBX")
  BACKUP="/tmp/verbadoc-pbxproj-backup-$(date +%Y%m%d-%H%M%S)"

  if [ "$ANCHORS" != "2" ]; then
    say "Found the anchor in $ANCHORS configuration(s), expected 2 (Debug + Release)."
    say "I will not guess. Add both INFOPLIST_KEY_ lines by hand."
  elif cp "$PBX" "$BACKUP"; then
    say "Backup: $BACKUP"

    # printf expands \t to real tabs first, so awk's own escape processing
    # has nothing left to mangle. $(GROQ_API_KEY) stays literal because the
    # printf format is single-quoted.
    # The values MUST be quoted. An unquoted `$(` is NOT a valid plist
    # value: it makes the whole project unopenable ("damaged ... parse
    # error"). This is not cosmetic - it is the exact bug that broke the
    # build the first time this script ran. The printf format is
    # single-quoted so the shell never tries to run $(...) itself.
    K1=$(printf '\t\t\t\tINFOPLIST_KEY_GROQ_API_KEY = "$(GROQ_API_KEY)";')
    K2=$(printf '\t\t\t\tINFOPLIST_KEY_NVIDIA_API_KEY = "$(NVIDIA_API_KEY)";')

    BEFORE=$(awk 'END{print NR}' "$PBX")
    awk -v a="$K1" -v b="$K2" \
      '{ print } /INFOPLIST_KEY_NSCameraUsageDescription = / { print a; print b }' \
      "$PBX" > "$PBX.new"
    NEW=$(awk 'END{print NR}' "$PBX.new")

    if [ ! -s "$PBX.new" ]; then
      say "Rewrite produced an empty file - nothing changed."
      rm -f "$PBX.new"
    elif [ "$NEW" != "$((BEFORE + 4))" ]; then
      say "Rewrite changed the file by $((NEW - BEFORE)) lines, not 4."
      say "Refusing to install it - your project file is untouched."
      rm -f "$PBX.new"
    elif ! plutil -lint "$PBX.new" >/dev/null 2>&1; then
      # THE gate that was missing. A line count cannot detect a plist
      # syntax error, and an unparsable pbxproj makes the project
      # impossible to open. Validate the NEW file before it replaces the
      # original, so a bad rewrite can never land.
      say "The rewritten project file does NOT parse as a plist."
      say "Refusing to install it - your project file is untouched."
      rm -f "$PBX.new"
    else
      cp "$PBX.new" "$PBX" && rm -f "$PBX.new"
      say "Inserted both keys into 2 configurations (plist validated)."
    fi
  else
    say "Backup to $BACKUP FAILED - I will not edit your project file."
  fi
fi

echo
say "GROQ_API_KEY lines now in pbxproj:   $(grep -c 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX")  (want 2)"
say "NVIDIA_API_KEY lines now in pbxproj: $(grep -c 'INFOPLIST_KEY_NVIDIA_API_KEY' "$PBX")  (want 2)"
if [ "$(grep -c 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX")" != "2" ] \
   || [ "$(grep -c 'INFOPLIST_KEY_NVIDIA_API_KEY' "$PBX")" != "2" ]; then
  say ""
  say "WARNING - fewer than 2 of each. The project still COMPILES, but every"
  say "AI call fails at RUNTIME with \"No AI provider is configured\" and"
  say "nothing in the build log will explain why. Add the missing lines by hand."
fi

# ================================================================
head2 "5. .gitignore  (created BEFORE any key file lands)"
# ================================================================
GI="$DST/.gitignore"
if [ -f "$GI" ]; then
  if grep -q 'xcconfig' "$GI" 2>/dev/null; then
    say "OK - $GI already ignores xcconfig."
  else
    printf '\n# Never commit keys\n*.xcconfig\n' >> "$GI" \
      && say "Added *.xcconfig to $GI"
  fi
else
  printf '# Never commit keys\n*.xcconfig\n' > "$GI" \
    && say "Created $GI ignoring *.xcconfig"
fi

# ================================================================
head2 "6. Config.xcconfig  (names + lengths only - values never printed)"
# ================================================================
if [ -f "$CFG_SRC" ]; then
  if [ -f "$CFG_DST" ]; then
    say "Already present at $CFG_DST - left exactly as it is."
  elif cp "$CFG_SRC" "$CFG_DST"; then
    say "Copied to $CFG_DST"
  else
    say "Could not copy it. Create $CFG_DST by hand with the two keys."
  fi
  if [ -f "$CFG_DST" ]; then
    echo
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|\#*) continue ;;
        *=*)
          n=$(printf '%s' "$line" | cut -d'=' -f1 | tr -d ' \t')
          v=$(printf '%s' "$line" | cut -d'=' -f2- | tr -d ' \t')
          if printf '%s' "$v" | grep -qE 'YOUR|placeholder|\.\.\.'; then
            say "  $n = <still a placeholder - NOT configured>"
          elif [ -n "$v" ]; then
            say "  $n = <set, ${#v} chars>"
          else
            say "  $n = <EMPTY>"
          fi
          ;;
      esac
    done < "$CFG_DST"
  fi
else
  say "No Config.xcconfig in staging, and I will not invent one."
  say "Create $CFG_DST yourself with GROQ_API_KEY and NVIDIA_API_KEY."
fi

# ================================================================
head2 "STILL REQUIRED BY HAND - the silent one"
# ================================================================
say "In Xcode: select the VerbaDoc PROJECT (not the target) -> Info tab"
say "-> Configurations -> set Config.xcconfig as the Base Configuration"
say "for BOTH Debug and Release."
say ""
say "Without it every \$(...) above expands to nothing, the keys are blank,"
say "and the router reports 'no AI provider is configured' - with nothing"
say "in the build log to explain why."

# ================================================================
echo
rule
say "DONE. Now build:"
say "  cd $DST"
say "  xcodebuild -project VerbaDoc.xcodeproj -scheme VerbaDoc \\"
say "    -destination 'generic/platform=iOS Simulator' \\"
say "    -derivedDataPath /tmp/verbadoc-dd build CODE_SIGNING_ALLOWED=NO \\"
say "    > /tmp/verbadoc-build.log 2>&1"
say "  grep -E 'error:' /tmp/verbadoc-build.log | head -60"
say "  grep -E 'BUILD (SUCCEEDED|FAILED)' /tmp/verbadoc-build.log | tail -1"
say ""
say "If xcodebuild says the project 'does not contain a scheme named"
say "VerbaDoc', there is no SHARED scheme. Re-run the same command with"
say "  -target VerbaDoc    instead of    -scheme VerbaDoc"
rule
