# Corpora

Sessions are **never committed**. Each corpus is a directory with a committed `MANIFEST.json`
whose `reproduce` line regenerates it byte for byte from (generator spec × oracle identity).
A manifest that drops a content-affecting flag is a lie about the only artifact we keep.

| stratum | where | who may read it |
|---|---|---|
| `train/` | here | porters, triage, everyone: rank it, diagnose it, fix against it |
| `probe-*/` | here | diagnostic strata; per-session reading allowed; never a forecast |
| sealed | **private repo `jon-bell/TwinCity-sealed`** | measure-only: never named in a brief, never diagnosed, scored on a cadence, aggregate-only history |

The sealed generator seed must never appear in this public repository: anyone with it, porter
agents included, could regenerate the exam.
