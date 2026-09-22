# hermes-deploy

git-mode: pr

<!-- direct = commit straight to main, tests run first, no PRs.
     pr     = branch + pull request + CI must pass before merge.
     See ~/AIHub/Standards/conventions/git-and-merge.md -->

**This repo is Mode B deliberately.** It has the heaviest paid-API surface in the
workspace, sends outward (email/SMS), and carries 13 CI workflows and ~1100 tests.
A mistake here costs real money or reaches real people, so changes go through a
pull request and CI has to be green before anything merges.

Claude runs the whole flow including the merge — Erik is told, not asked.
