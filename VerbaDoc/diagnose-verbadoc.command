#!/bin/bash
# ================================================================
#  VerbaDoc - diagnose + fix the AI key wiring
#
#  One run answers:
#    0. Does it build?              (compiler errors, verbatim)
#    1. Are the API keys wired?     (patches project.pbxproj safely)
#    2. What do the AI call sites actually call?   (tells us who is right)
#    5. Is the Capy Surfers game actually hosted?  (SpriteView)
#    6. Are the emoji still in the shipped UI?
#    7. The possible build blocker (a duplicated viewAppearTime)
#
#  It writes at most TWO files, both named in its own output:
#    - VerbaDoc.xcodeproj/project.pbxproj  (one build-setting line per
#      configuration, after a timestamped backup written to /tmp)
#    - Config.xcconfig, ONLY if it is missing (created with placeholders)
#  The build-setting line it inserts is a VARIABLE REFERENCE. A key value
#  is never written anywhere and never printed.
#
#  Run:  bash ~/Desktop/VerbaDoc/VerbaDoc/diagnose-verbadoc.command
# ================================================================

set -u

say()  { printf '%s\n' "$*"; }
rule() { printf '%.0s=' $(seq 1 72); echo; }
head2() { echo; rule; say "$*"; rule; }

PROJ="/Users/zoey/Desktop/VerbaDoc/VerbaDoc"
SRC="$PROJ/VerbaDoc"
CFG="$PROJ/Config.xcconfig"

if [ ! -d "$PROJ" ]; then
  say "STOP: $PROJ does not exist. Nothing was changed."
  exit 1
fi

# Resolve the project ONE time, so the build and the pbxproj patch always act
# on the SAME project. Prefer VerbaDoc.xcodeproj: this repo also contains a
# stale VerbaDoc4.xcodeproj, which a bare `find | head -1` could pick.
XP=""
if [ -f "$PROJ/VerbaDoc.xcodeproj/project.pbxproj" ]; then
  XP="$PROJ/VerbaDoc.xcodeproj"
else
  CANDIDATES=$(find "$PROJ" -maxdepth 3 -name '*.xcodeproj' -not -path '*/.git/*' 2>/dev/null)
  PREFERRED=$(printf '%s\n' "$CANDIDATES" | grep '/VerbaDoc\.xcodeproj$' | head -1)
  if [ -n "$PREFERRED" ]; then
    XP="$PREFERRED"
  else
    XP=$(printf '%s\n' "$CANDIDATES" | head -1)
  fi
fi

PBX=""
STALE=0
if [ -n "$XP" ]; then
  PBX="$XP/project.pbxproj"
fi

say "VerbaDoc diagnostic"
say "Project folder: $PROJ"

# ================================================================
head2 "0. BUILD  (this is priority zero - nothing else matters if it fails)"
# ================================================================
if [ -z "$XP" ]; then
  say "No .xcodeproj found anywhere under $PROJ, so I cannot build it."
  say ">> Tell me where the project file actually is."
else
  say "Building: $XP"
  case "$XP" in
    */VerbaDoc.xcodeproj) ;;
    *) say "NOTE: that is NOT VerbaDoc.xcodeproj - it may be a stale copy." ;;
  esac
  # This is a HEURISTIC, not proof: it errs toward NOT editing, so a miss
  # means we skip a patch the user needs rather than touching a stale file.
  # The filename alone does not prove the project is live: this repo is known
  # to contain a stale VerbaDoc4 project with zero sources. Check contents,
  # and match loosely (quoted or unquoted) so the guard cannot silently miss.
  case "$XP" in
    */VerbaDoc4.xcodeproj) STALE=1 ;;
  esac
  if grep -q 'VerbaDoc4' "$XP/project.pbxproj" 2>/dev/null \
     && ! grep -qE 'productName = "?VerbaDoc"?' "$XP/project.pbxproj" 2>/dev/null; then
    STALE=1
  fi
  if [ "$STALE" = "1" ]; then
    say "WARNING: this looks like a STALE copy (VerbaDoc4), not the live project."
    say "Nothing below is trustworthy until we find the real one, and I will not"
    say "edit this project's build settings."
    say "Other .xcodeproj files under $PROJ:"
    find "$PROJ" -maxdepth 3 -name '*.xcodeproj' -not -path '*/.git/*' 2>/dev/null
  fi
  # Everything below uses absolute paths, so a failed cd must not abort.
  cd "$(dirname "$XP")" 2>/dev/null || say "NOTE: could not cd to the project folder."
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    say "NOTE: no Xcode at /Applications/Xcode.app - using the active toolchain."
  fi
  # Missing xcodebuild must skip ONLY this section, not abort the script -
  # the other five questions still have answers to give.
  CAN_BUILD=1
  if ! command -v xcodebuild >/dev/null 2>&1; then
    say "xcodebuild is not on PATH, so I cannot build. Section 0 is skipped;"
    say "everything below still runs."
    CAN_BUILD=0
  fi

  if [ "$CAN_BUILD" = "1" ]; then
    SCHEME=$(basename "$XP" .xcodeproj)
    BUILD_LOG=/tmp/verbadoc-build.log
    say "(building - this takes a few minutes. Full log: $BUILD_LOG)"
    xcodebuild -project "$XP" -scheme "$SCHEME" \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath /tmp/verbadoc-dd build CODE_SIGNING_ALLOWED=NO \
      > "$BUILD_LOG" 2>&1
    grep -E 'error:|BUILD (SUCCEEDED|FAILED)' "$BUILD_LOG" | head -60
    echo
    say "--- FINAL STATUS (always printed, in case the 60 lines above cut it off) ---"
    grep -E 'BUILD (SUCCEEDED|FAILED)' "$BUILD_LOG" | tail -1
    if ! grep -qE 'BUILD (SUCCEEDED|FAILED)' "$BUILD_LOG"; then
      say ""
      say "No BUILD result line appeared - the scheme name probably does not match."
      say "Schemes xcodebuild can see for this project:"
      xcodebuild -list -project "$XP" 2>&1 | head -30
    fi
  fi
fi

# ================================================================
head2 "1. API KEY WIRING"
# ================================================================

# --- Config.xcconfig -------------------------------------------------
if [ -f "$CFG" ]; then
  say "Config.xcconfig: present. Contents (placeholder values shown only if you"
  say "have not filled them in yet - your real keys are NOT printed here):"
  say ""
  # Print the KEY NAMES and whether each looks filled in - never the value.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      *=*)
        name=$(printf '%s' "$line" | cut -d'=' -f1 | tr -d ' \t')
        val=$(printf '%s' "$line" | cut -d'=' -f2- | tr -d ' \t')
        if printf '%s' "$val" | grep -qE 'YOUR|placeholder|\.\.\.'; then
          say "  $name = <still a placeholder - NOT configured>"
        elif [ -n "$val" ]; then
          say "  $name = <set, ${#val} chars>"
        else
          say "  $name = <EMPTY>"
        fi
        ;;
    esac
  done < "$CFG"
else
  say "Config.xcconfig: MISSING - creating it with placeholder values."
  cat > "$CFG" <<'XCCONFIG'
// VerbaDoc local secrets. This file is gitignored - never commit it.
// Fill in the two values below, then rebuild.

GROQ_API_KEY = gsk_YOUR_GROQ_KEY_HERE
NVIDIA_API_KEY = nvapi_YOUR_NVIDIA_KEY_HERE
XCCONFIG
  say "Created: $CFG"
  say ">> Now open it and replace both placeholders with your real keys."
fi

say ""
say "--- is Config.xcconfig ignored by git? ---"
if ! git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1; then
  say "Not a git repository at $PROJ - skipping the ignore check."
elif git -C "$PROJ" check-ignore -q "$CFG" 2>/dev/null; then
  say "OK - Config.xcconfig is gitignored."
else
  say "WARNING - Config.xcconfig is NOT gitignored. Do not commit until it is."
fi

# --- project.pbxproj -------------------------------------------------
say ""
say "--- project.pbxproj ---"
if [ ! -f "$PBX" ]; then
  say "Cannot find $PBX - skipping the build-setting step."
elif [ "$STALE" = "1" ]; then
  say "The only project I found looks STALE, so I am NOT editing its build settings."
  say "Point me at the real VerbaDoc.xcodeproj and re-run, or add the setting by hand."
else
  if grep -q 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX"; then
    say "INFOPLIST_KEY_GROQ_API_KEY is already present - no change made."
  elif ! grep -q 'INFOPLIST_KEY_NSCameraUsageDescription = ' "$PBX"; then
    say "Anchor line (INFOPLIST_KEY_NSCameraUsageDescription) not found, so I will"
    say "NOT guess where to insert. Add this by hand to the VerbaDoc TARGET's"
    say "Build Settings, for BOTH Debug and Release:"
    say "    INFOPLIST_KEY_GROQ_API_KEY = \$(GROQ_API_KEY);"
  else
    # A failed backup costs the PATCH, not the whole run - sections 2/5/6/7
    # still have answers to give.
    CAN_PATCH=1
    BACKUP="/tmp/verbadoc-pbxproj-backup-$(date +%Y%m%d-%H%M%S)"
    if cp "$PBX" "$BACKUP"; then
      say "Backup: $BACKUP"
    else
      say "Backup to $BACKUP failed - I will NOT edit your project file."
      CAN_PATCH=0
    fi

    # Same indentation as the anchor line, so the file stays readable.
    INJECT=$(printf '\t\t\t\tINFOPLIST_KEY_GROQ_API_KEY = $(GROQ_API_KEY);')
    BEFORE=$(grep -c 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX" 2>/dev/null)
    BEFORE=${BEFORE:-0}

    # awk -v assigns the string literally, so "$(GROQ_API_KEY)" is NOT expanded.
    awk -v ins="$INJECT" \
      '{ print } /INFOPLIST_KEY_NSCameraUsageDescription = / { print ins }' \
      "$PBX" > "$PBX.new"

    # awk counts a final unterminated line too, unlike `wc -l`.
    LINES_BEFORE=$(awk 'END{print NR}' "$PBX")
    LINES_NEW=$(awk 'END{print NR}' "$PBX.new")

    if [ ! -s "$PBX.new" ]; then
      say "Rewrite produced an empty file - nothing changed."
      rm -f "$PBX.new"
    elif [ "$LINES_NEW" != "$((LINES_BEFORE + 2))" ]; then
      say "Rewrite changed the file by $((LINES_NEW - LINES_BEFORE)) lines, not 2."
      say "Refusing to install it - your project file is untouched."
      rm -f "$PBX.new"
    elif [ "$CAN_PATCH" = "0" ]; then
      say "Refusing to install the rewrite with no backup - your file is untouched."
      rm -f "$PBX.new"
    else
      cp "$PBX.new" "$PBX" && rm -f "$PBX.new"
      AFTER=$(grep -c 'INFOPLIST_KEY_GROQ_API_KEY' "$PBX" 2>/dev/null)
      AFTER=${AFTER:-0}
      ADDED=$((AFTER - BEFORE))
      if [ "$ADDED" = "2" ]; then
        say "Added INFOPLIST_KEY_GROQ_API_KEY to 2 configurations (Debug + Release)."
      else
        say "Inserted into $ADDED configs instead of 2 - restoring from the backup."
        cp "$BACKUP" "$PBX"
      fi
    fi
  fi
fi

say ""
say "STILL REQUIRED BY HAND (this is the silent-failure step):"
say "  In Xcode: select the VerbaDoc PROJECT (not the target) -> Info tab"
say "  -> Configurations -> set Config.xcconfig as the Base Configuration"
say "  for BOTH Debug and Release."
say "  Without it, \$(GROQ_API_KEY) expands to nothing and the key is blank."
if [ -z "$PBX" ] || [ ! -f "$PBX" ]; then
  say ""
  say "No project.pbxproj was found, so I cannot check whether Config.xcconfig"
  say "is attached. Do the Base Configuration step above by hand."
elif grep -q 'Config.xcconfig' "$PBX" 2>/dev/null; then
  say ""
  say "pbxproj mentions Config.xcconfig, so it appears to be attached already."
else
  say ""
  say "Config.xcconfig does not appear in pbxproj, so it is probably not"
  say "attached yet. Do the Base Configuration step above. This failure is"
  say "silent - confirm at runtime, where APIKey.isConfigured(...) must print"
  say "true."
fi

# ================================================================
head2 "2. WHAT DO THE AI CALL SITES ACTUALLY CALL?"
# ================================================================
# Search $SRC when it exists, else the whole project folder. An explicit
# search target (not the cwd) - otherwise a project resolved elsewhere can
# leave the later sections grepping the wrong tree and reporting a
# confident but false "none found".
SCAN="$PROJ"
if [ -d "$SRC" ]; then
  SCAN="$SRC"
else
  say "NOTE: $SRC does not exist - searching the whole project folder instead."
  say "(Expect hits from any stale copy that lives under it.)"
fi

for pat in 'AIChatRouter' 'AIChatService' 'GroqAPI' 'StudyGenService' 'StudyGenChatClient' 'NVIDIAAIService' 'api\.groq\.com' 'integrate\.api\.nvidia\.com'; do
  echo
  say "--- refers to: $pat ---"
  grep -rn --include='*.swift' -E "$pat" "$SCAN" 2>/dev/null | head -12
  grep -rq --include='*.swift' -E "$pat" "$SCAN" 2>/dev/null || say "    (no matches)"
done

echo
say "--- Info.plist key names this code expects ---"
grep -rn --include='*.swift' -E 'infoPlistKey|NVIDIA_API_KEY|GROQ_API_KEY' "$SCAN" 2>/dev/null | head -20

# ================================================================
head2 "5. IS THE GAME HOSTED?  (SpriteView)"
# ================================================================
say "Searching: $SCAN"
grep -rn --include='*.swift' -E 'SpriteView|GameScene\(' "$SCAN" 2>/dev/null | head -15
grep -rq --include='*.swift' -E 'SpriteView' "$SCAN" 2>/dev/null \
  || say "    No SpriteView in the sources searched -> the scene is never hosted. That is the bug."

# ================================================================
head2 "6. EMOJI STILL IN THE UI?"
# ================================================================
say "Searching: $SCAN"grep -rn --include='*.swift' -E '🔥|💡|✨' "$SCAN" 2>/dev/null | head -15
grep -rq --include='*.swift' -E '🔥|💡|✨' "$SCAN" 2>/dev/null || say "    None found."

# ================================================================
head2 "7. THE POSSIBLE BUILD BLOCKER"
# ================================================================
say "Searching: $SCAN"GUARD="$SRC/Features/Practice/StudyGuideView.swift"
if [ -f "$GUARD" ]; then
  say "--- viewAppearTime in StudyGuideView.swift (should appear once as @State) ---"
  grep -n 'viewAppearTime' "$GUARD"
else
  say "Not found at $GUARD - the live sources may be somewhere else entirely."
  say "Searching the whole project folder for it:"
  find "$PROJ" -name 'StudyGuideView.swift' -not -path '*/.git/*' 2>/dev/null
fi

# ================================================================
echo
rule
say "DONE - copy this whole output back."
rule
