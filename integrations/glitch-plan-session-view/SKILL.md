---
name: glitch-plan-session-view
description: Companion contract for explicit interactive checkpoints in glitch-plan outputs and their execution. Does not replace glitch-plan or change fleet/BWPM work.
license: MIT
---

# Interactive plan checkpoint contract

CodexBWAI, COMMANDER-993. English-first companion to the existing `/glitch-plan` and `/glitch-execute` workflows. This is a distributable integration contract, not an installed override of the managed skills.

## When writing or deliberately revising an interactive plan

Follow `/glitch-plan` normally: resolve the task/home, settle the owner's choices, write its implementation detail and validation, and retain its Build choices. This companion adds one explicit checkpoint block to that same canonical plan. No additional state file, fleet ticket or task manager is created.

1. Agree the visible checkpoint names with the owner through the planning workflow. Use short English outcome descriptions by default. Never invent an approval or hide a gate to make a checkpoint look finished.
2. Generate a block using the installed reader, for example:

   `session-list template --title "CSV import" --step "Implement the parser" --step "Prove the import" --step "Review and land the change"`

   The command only prints a block; it does not write a file. Put that output into the canonical plan through the plan writer's normal permitted write path. Preserve its generated stable `plan_id` for the life of the plan. There must be exactly one `TERN-SESSION` block.
3. Keep detailed implementation steps and dated `## Progress` logs as they are. The checkpoint block is the explicit current-state summary, not a prose parser. Keep the sole START HERE marker under the existing session-hygiene rules.
4. Existing plans gain a block only when explicitly resumed/revised for this workflow. Do not batch-convert old plans or infer checkbox completion from dated prose.

## During interactive execution

The executor that owns the canonical plan owns its checkpoint block. When starting a checkpoint set it `active` and set `current` to its stable id. At most one checkpoint is active. If it is waiting, use `blocked` with a concrete `reason`, keeping `current` on that checkpoint. Mark `done` only when the agreed outcome has been verified; clear `current` if no active/blocked checkpoint is current. Preserve ids when editing descriptions or reordering steps.

Update the dated Progress evidence, checkpoint state and START HERE consistently in the same canonical file. Never treat a green test alone as owner acceptance, release permission or a reason to bypass another gate. The view does not write any of these values.

## Attaching the view

In the Tern tab that displays the interactive session, choose **Interactive plan: attach to this tab**. Select Local if the file is accessible on that Tern session host; select SSH for an explicitly approved ordinary SSH destination and the plan's absolute path there. “Local” is relative to the session host, not necessarily the desktop showing the window.

The view pins the selected source and its stable plan id. It polls read-only and shows active, blocked, pending and done checkpoints. Different plan ids at the same path are refused. No agent prompt, source write, task takeover or fleet dispatch occurs. Existing gates remain in the plan.

For SSH, the destination must support ordinary noninteractive POSIX commands and existing key authentication, trust and Python 3. Forced agent launch aliases (`seat-*`) are refused. If an SSH-launched agent and its Tern session host share the same plan filesystem, use Local; do not forward another Unix identity's socket or credentials.

## Deployment boundary

The managed Glitch engine remains read-only. Integrate this companion through a reviewed supported customization or upstream skill change; do not edit a live managed `glitch-plan`/`glitch-execute` file or install hooks automatically. Before claiming end-to-end live adoption, prove an actual new interactive plan receives the block, its executor maintains it and the real local/SSH panel reflects its verified checkpoint changes. Fleet execution uses its own workflow; BWPM/FORGE are not panel sources.
