#!/bin/bash
# ================================================================
#  VerbaDoc - safe WIP snapshot
#
#  Commits + pushes your CURRENT working tree, broken or not, so an
#  advisor can read the real state instead of a stale snapshot.
#
#  It REFUSES to commit if it finds something that looks like a live
#  API key in anything git would publish.
#
#  Run it with:
#     bash ~/Desktop/VerbaDoc/VerbaDoc/snapshot-verbadoc.command
# ================================================================

set -u

SCRIPT_NAME="$(basename "$0")"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$SCRIPT_NAME"
STOP=0

say()  { printf '%s\n' "$*"; }
rule() { printf '%.0s-' $(seq 1 62); echo; }

# --- find the repo ----------------------------------------------
REPO=""
for candidate in "/Users/zoey/Desktop/VerbaDoc/VerbaDoc" "/Users/zoey/Desktop/VerbaDoc"; do
  if [ -d "$candidate" ] && git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO="$(git -C "$candidate" rev-parse --show-toplevel)"
    break
  fi
done

if [ -z "$REPO" ]; then
  say "STOP: could not find a git repository near /Users/zoey/Desktop/VerbaDoc."
  say "Nothing was changed."
  exit 1
fi

cd "$REPO" || exit 1

rule
say "VerbaDoc - safe WIP snapshot"
say "Repo: $REPO"
rule
echo

# --- stage ------------------------------------------------------
say "Staging everything..."
if ! git add -A; then
  say "STOP: 'git add' failed. Nothing was committed."
  exit 1
fi
# Never commit the helper scripts themselves. Matched by glob, not by
# basename: the repo root may be the script's directory OR its parent,
# and a relative pathspec silently misses in the second case. The glob
# covers both snapshot-verbadoc.command and diagnose-verbadoc.command.
git reset -q -- '*-verbadoc.command' 2>/dev/null || true

echo
say "Abort-checks"
rule

# 1. A secrets file must never be published.
SECRET_FILES="$(git diff --cached --name-only | grep -iE '\.xcconfig$|\.env$|secret|credential' || true)"
if [ -n "$SECRET_FILES" ]; then
  say "STOP - a secrets file is about to be committed:"
  say "$SECRET_FILES"
  STOP=1
fi

# 2. A live-looking key in code or config is a hard stop.
CODE_HITS="$(git diff --cached -U0 -- ':(exclude)*.md' \
  | grep -nE '(gsk_|nvapi-|sk-ant-|sk-proj-|AIza)[A-Za-z0-9_-]{20,}' || true)"
if [ -n "$CODE_HITS" ]; then
  say "STOP - a live-looking API key is in the staged changes:"
  say "$CODE_HITS"
  STOP=1
fi

# 3. The same pattern in a markdown file is usually just an example.
DOC_HITS="$(git diff --cached -U0 -- '*.md' \
  | grep -nE '(gsk_|nvapi-|sk-ant-|sk-proj-|AIza)[A-Za-z0-9_-]{20,}' || true)"
if [ -n "$DOC_HITS" ]; then
  say "WARNING - key-like text found in a markdown file (likely just an example):"
  say "$DOC_HITS"
  echo
fi

if [ "$STOP" = "1" ]; then
  # Only claim a clean-up that actually happened.
  if git reset -q 2>/dev/null; then
    say "Nothing was committed, and nothing was left staged."
  else
    # No HEAD yet (a repo with no commits), so 'git reset' cannot run.
    if git rm -r --cached -q . >/dev/null 2>&1; then
      say "Nothing was committed. The staging area was cleared."
    else
      say "Nothing was committed, but the staging area could NOT be cleared."
      say "Do not commit from Xcode until the flagged key is removed."
    fi
  fi
  echo
  say "Your FILES are untouched - nothing was deleted or modified."
  echo
  say "How to unblock, depending on what was flagged:"
  echo
  say "  - A key inside a .swift file:"
  say "        delete the literal, keep loading it from Config.xcconfig,"
  say "        then ROTATE that key."
  echo
  say "  - A secrets file is staged (Config.xcconfig, .env, ...):"
  say "    Use the EXACT file name printed at the top of this section, in"
  say "    both lines below. With Config.xcconfig that reads:"
  say "        echo 'Config.xcconfig' >> .gitignore"
  say "        git rm --cached Config.xcconfig"
  say "    If it was NEVER committed before, only the first line is needed."
  say "    If it WAS committed before, you need BOTH - the file is still"
  say "    tracked, and the .gitignore line on its own would just be"
  say "    re-staged by the next 'git add -A'."
  say "    Then run this script again, and ROTATE that key - ignoring a"
  say "    file does not remove it from the repo's existing history."
  exit 1
fi

say "OK - no secrets file staged."
say "OK - no live-looking key in code or config."
echo

# --- show what is going in --------------------------------------
say "About to commit:"
rule
git diff --cached --stat | tail -30
echo
say "Changed files: $(git diff --cached --name-only | wc -l | tr -d ' ')"
echo

# --- commit -----------------------------------------------------
if git diff --cached --quiet; then
  say "Nothing new to commit - the working tree is already clean."
else
  if ! git commit -q -m "WIP: current state snapshot"; then
    say "STOP: 'git commit' failed. Nothing was pushed."
    exit 1
  fi
  say "Committed $(git rev-parse --short HEAD)"
fi
echo

# --- remote -----------------------------------------------------
say "Remote:"
rule
git remote -v
rule
echo

if [ -z "$(git remote)" ]; then
  say "There is NO remote configured, so there is nothing to push to."
  echo
  say "Two options:"
  say "  A) Create a PRIVATE GitHub repo, then run these two lines:"
  say "       git remote add origin <YOUR-REPO-URL>"
  say "       bash \"$SELF\""
  say "  B) Skip git and hand your advisor a zip instead:"
  say "       cd \"$REPO/..\""
  say "       zip -r verbadoc-source.zip VerbaDoc -x '*Config.xcconfig'"
  exit 0
fi

# --- push -------------------------------------------------------
say "IMPORTANT - check that the repo above is PRIVATE."
say "If it is public, everything in it becomes public the moment you push."
say "Pushing in 6 seconds. Press Ctrl-C now if you want to check first."
sleep 6
echo

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  say "Pushing..."
  git push
  PUSHED=$?
else
  say "No upstream branch set - pushing and setting it..."
  git push -u origin HEAD
  PUSHED=$?
fi

echo
if [ "$PUSHED" = "0" ]; then
  say "DONE - pushed $(git rev-parse --short HEAD)."
  echo
  say "Send back the URL shown in the 'Remote:' block above."
  echo
  say "To undo the commit later (your files are kept exactly as they are):"
  say "     git reset --soft HEAD~1"
  say "     (if this was your very first commit: git update-ref -d HEAD)"
  say "If you also need the push undone, ask me first - do not force-push."
else
  say "PUSH FAILED (exit $PUSHED). Your commit is safe locally."
  echo
  say "If it said 'rejected' or 'non-fast-forward':"
  say "     git pull --rebase"
  say "     git push"
  say "If THAT conflicts on project.pbxproj, do not hand-merge it:"
  say "     git checkout --theirs project.pbxproj"
  say "     git add project.pbxproj && git rebase --continue"
  say "     git push"
  say "Still stuck? Copy this whole output back to me."
fi
