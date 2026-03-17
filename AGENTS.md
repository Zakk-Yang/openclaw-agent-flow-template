# Project Instructions

## Purpose

This repo is a starter for building a project-local OpenClaw agent flow.

Users are expected to edit this file for their own project. Keep it plain and practical:

- state the project goal clearly
- define what counts as safe work
- define what files each agent may or may not touch
- prefer bounded tasks over broad autonomous rewrites

## Default Safety Rules

- Do not use destructive git commands unless the user explicitly asks.
- Do not revert unrelated working tree changes.
- Keep prompts, roles, and setup scripts inside the repo.
- Prefer small, verifiable changes.
- If the best action is to report a blocker, do that instead of forcing a bad change.

## GSD Use

This template is designed to work well with GSD discipline:

- inspect current state
- pick one bounded next task
- execute safely
- verify what changed
- record blockers clearly
