#!/usr/bin/env bash
# Vercel's "Ignored Build Step" (vercel.json `ignoreCommand`), run from
# apps/web before every build. Exit 0 skips the build; exit 1 builds.
#
#   main         always builds (production, stall10.app)
#   development  builds only when the website changed: apps/web, or
#                packages/ (@stall10/shared is compiled into the site)
#   anything else never builds
#
# Vercel sets VERCEL_GIT_COMMIT_REF (the branch) and
# VERCEL_GIT_PREVIOUS_SHA (the last commit deployed from this branch).

branch="${VERCEL_GIT_COMMIT_REF:-}"

case "$branch" in
  main)
    echo "main: building production."
    exit 1
    ;;
  development)
    ;;
  *)
    echo "Skipping: only development and main deploy (this is '$branch')."
    exit 0
    ;;
esac

base="${VERCEL_GIT_PREVIOUS_SHA:-}"
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  # No earlier deployment, or it's outside Vercel's shallow clone: compare
  # with the previous commit, and build if even that isn't available.
  base="HEAD^"
  if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    echo "development: no earlier commit to compare with; building."
    exit 1
  fi
fi

git diff --quiet "$base" HEAD -- . ../../packages
status=$?
if [ "$status" -eq 0 ]; then
  echo "development: apps/web and packages/ unchanged since $base; skipping."
  exit 0
fi
echo "development: the website changed since $base; building."
exit 1
