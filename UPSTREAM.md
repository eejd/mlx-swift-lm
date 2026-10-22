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

### `topic/minicpm5-tool-call-format`

| Upstream PR | Status |
|---|---|
| none yet | not-submitted (no upstream contact before the quantbench + agentbench soak, ADR-0008); tracked in eejd/swift-lm#8. `git apply --check` passes against `ml-explore/mlx-swift-lm` `main` (`bb0d5b0`); it was not built there |

MiniCPM5 (`model_type` `llama`, vocabulary 130560) was given the Llama 3 format by the architecture heuristic and its `<function name="f"><param name="k">v</param></function>` calls stayed response text. Adds `ToolCallFormat.minicpm5` and `MiniCPM5ToolCallParser` (CDATA values, parallel calls, schema-typed arguments, markup tolerated without CDATA), selects it from the chat template or `tool_parser_type: minicpm5`, and adds `ToolCallParser.frameEnd(in:)` so the streaming processor and the recovery scanner agree on where a call whose value may contain its own close tag ends.


### `topic/declared-tools-authoritative`

| Upstream PR | Status |
|---|---|
| none yet | not-submitted (no upstream contact before the quantbench + agentbench soak, ADR-0008); tracked in eejd/swift-lm#9. `git apply --check` passes against `ml-explore/mlx-swift-lm` `main` (`bb0d5b0`) for every file but `Evaluate.swift` (its draft-model `generate` is SharpAI's); not built there |

With `tools: []` (a request that offers no tools) JSON without a protocol marker is response text, not a call to an undeclared function that is rejected and dropped (a Llama 3 format model answering `{"name": "Jane Doe", "age": 31}`); marked attempts are still rejected, `nil` and a nonempty list behave as before. The draft-model `generate` accepted `tools:` and dropped it and the tool-call policy.


## Tags

Release tags on `local` are `v<base>-local<NN>` (docs/development-model.md, ADR-0008 §2), `<base>` being the last release of the primary upstream (`ml-explore/mlx-swift-lm`) that `local` contains. `local`'s base `4d76a2e` is also the release `b874` of the secondary upstream (`SharpAI/mlx-swift-lm` tags build counters `b<N>`; `git rev-parse b874` is `4d76a2e7852f8111d36edb5f58b8dcd0aa6d9fe2`), but ADR-0008 counts one primary upstream per repo and the primary's release is what `local` contains by ancestry: `3.32.3` (`git merge-base --is-ancestor 3.32.3 local`; `local` is 379 commits past it, most of them SharpAI's). `<base>` is therefore `3.32.3`, the same reading as `eejd/rs-mlxcel` (`v0.7.0-local01` on an unreleased `main`). A later re-cut onto a newer SharpAI release keeps `3.32.3` and continues the counter (`local02`) until `local` contains a newer `ml-explore` release.

| Tag | Commit | Contents | Checked |
|---|---|---|---|
| `v3.32.3-local01` (annotated, tag object `ce69dd736dcd587a979ec8776b55aa032d816a6f`) | `d5e92196e0709e377dd6a5a5fe2971bc73aafe1d` (`local` after the merge of #2, 2026-10-22) | `SharpAI/mlx-swift-lm@4d76a2e` + `UPSTREAM.md` + `topic/minicpm5-tool-call-format` (#1) + `topic/declared-tools-authoritative` (#2). Against `4d76a2e` the tag changes 12 files under `Libraries/MLXLMCommon`, `Tests/MLXLMTests` and `UPSTREAM.md`; `Package.swift` and `Package.resolved` are unchanged, so the dependency list of the consuming port is unchanged. The tag's `UPSTREAM.md` is the one before this Tags section (documentation only). | `MiniCPM5ToolCallTests` and the tool suites pass on a scratch tree built like the port `swiftlm-local` (see eejd/macports-ports-local); live probes in eejd/py-quantbench#292 on the same Libraries |

The tag is the library input of `eejd/swift-lm` `v861-local01` (distfile `mlx-swift-lm-3.32.3-local01.tar.gz` of the port `swiftlm-local`); the two are one release unit (see `eejd/swift-lm` `UPSTREAM.md`, "Merge and port order"). `eejd/swift-lm`'s submodule gitlink is not moved to this tag: it names `SharpAI/mlx-swift-lm` as its URL.

## Origin

Developed 2026-10-22 from the T0 engine runs of eejd/py-quantbench (#217, #287) against SwiftLM b861: eejd/swift-lm#7, #8, #9.
