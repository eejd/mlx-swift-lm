# Upstream and adopted work (`local` branch)

Primary upstream: `ml-explore/mlx-swift-lm` (GitHub fork parent). Secondary upstreams tracked: `SharpAI/mlx-swift-lm` (`track/SharpAI/main`).

`local` is `SharpAI/mlx-swift-lm@4d76a2e` (below) plus the topic branches. `main` mirrors `ml-explore/mlx-swift-lm` `main` (fast-forward only).

## Adopted from other repos

| What | Source | Also a topic? |
|---|---|---|
| The whole tree at the base of `local` | `SharpAI/mlx-swift-lm@4d76a2e7852f8111d36edb5f58b8dcd0aa6d9fe2` (merge of PR #83): the `mlx-swift-lm` that SwiftLM b861 pins and the MacPorts port `swiftlm` builds | no |

`local` is a descendant of `track/SharpAI/main`, not of `main`: SharpAI's fork carries 331 commits that `ml-explore/mlx-swift-lm` does not have (Gemma 4, MTP, SSD streaming, GPU/CPU layer partitioning, ...), and `main` had 8 that it lacked (measured against `ml-explore/mlx-swift-lm@bb0d5b0` on 2026-10-22). The tool-call layer (`Libraries/MLXLMCommon/Tool`) is the same in both except `ToolCallFormat.swift`.

## Topic branches

Each topic is based on the base commit above. Applies to `ml-explore/mlx-swift-lm` `main` means `git apply --check` of the topic's diff against the commit named; it was not built there.

<!-- topic/minicpm5-tool-call-format -->

<!-- topic/declared-tools-authoritative -->

## Origin

Developed 2026-10-22 from the T0 engine runs of eejd/py-quantbench (#217, #287) against SwiftLM b861: eejd/swift-lm#7, #8, #9.
