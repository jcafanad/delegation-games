# DDG Architecture: Dialectical Delegation Games

This document describes the design of the DDG sublibrary (`lib/dialectical/`), its theoretical grounding, and the rationale for key architectural decisions.

---

## Overview

DDG (Delegation as Dialectical) is the third protocol in the DIG → DEC → DDG trajectory. Where DIG and DEC optimize scalar utility, DDG maps the **structure of argumentation** — specifically which contradictions a delegation network makes visible, and which it erases.

The payload changes: instead of a task with a float reward, DDG passes an **Argument** (claim + grounds + defeaters) through the network. The terminal value is a **Belnap truth value** (T/F/B/N), not a reward. B (contradictory) is a valid finding, not a failure.

---

## Four-Layer Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Layer 4: Protocol (Make_DDG functor)                    │
│  protocol_ddg.ml                                         │
│  - traversal loop                                        │
│  - B-state termination                                   │
│  - dialogue_trace accumulation                           │
└────────────────────┬─────────────────────────────────────┘
                     │ uses
┌────────────────────▼──────────────┐  ┌────────────────────────────────┐
│  Layer 3: Topology (TOPOLOGY sig) │  │  Layer 2: Framework (FRAMEWORK) │
│  dialectical_topology.ml          │  │  argumentation_framework.ml      │
│  paramo_topology.ml               │  │                                  │
│  - get_attackers(F → burden)      │  │  - evaluate ~agent_id ~arg       │
│  - get_defenders(T → reinforce)   │  │  - find_defeaters ~agent_id ~arg │
│  - get_arbiters (N → expertise)   │  │  - returns truth_val             │
└───────────────────────────────────┘  └────────────────────────────────┘
                     │ both use
┌────────────────────▼─────────────────────────────────────┐
│  Layer 1: Argument (argument.ml)                         │
│  - id, claim : string                                    │
│  - grounds : string list (fixed at creation)             │
│  - defeaters : string list (mutable, accumulates)        │
└──────────────────────────────────────────────────────────┘
```

Each layer is independently swappable. You can use `Dung_framework` with `Paramo_topology`, or `Make_paramo_framework` with `Fallback_topology`. The `Make_DDG` functor takes one topology module and one framework module:

```ocaml
module Make_DDG
    (Topo : TOPOLOGY)
    (Framework : FRAMEWORK)
  : DDG
```

---

## Layer 1: Argument

`lib/dialectical/argument.ml`

An argument is a structured proposition travelling through the network:

```ocaml
type t = {
  id       : string;
  claim    : string;
  grounds  : string list;
  mutable defeaters : string list;
}
```

**Why mutable defeaters?**

Defeaters *accumulate* as the argument traverses the network. Each agent may add new defeaters based on local knowledge and structural position. This models how contradictions emerge through *engagement* — not as pre-existing failures but as the relational outcome of argument meeting opposition.

**Predefined Páramo arguments:**

| Constructor | Claim | Grounds | Advancing actor |
|---|---|---|---|
| `paramo_ecosystem_argument()` | "ecosystem services framework should govern Páramo commons" | water regulation + carbon sequestration | State / Environmental agency |
| `paramo_territorial_argument()` | "territorial autonomy is the legitimate basis for Páramo governance" | generational habitation + FPIC rights | Paramuno communities |
| `paramo_development_argument()` | "development projects should proceed in Páramo zone" | economic growth + frontier integration | State |

---

## Layer 2: Argumentation Framework

`lib/dialectical/argumentation_framework.ml`

The `FRAMEWORK` interface:

```ocaml
module type FRAMEWORK = sig
  val evaluate    : agent_id:Agent_id.t -> arg:Argument.t -> truth_val
  val find_defeaters : agent_id:Agent_id.t -> arg:Argument.t -> string list
end
```

`evaluate` returns the agent's epistemic verdict on the argument. `find_defeaters` returns any new defeaters this agent contributes (added to `arg.defeaters` before routing).

### Available Frameworks

**`Dung_framework`** — evidence-based, agent-agnostic

Counts grounds vs defeaters:
- 0 grounds, 0 defeaters → N
- defeaters = 0 → T
- defeaters > grounds → F
- defeaters = grounds → B
- grounds > defeaters → T

Ignores agent identity entirely. Useful as a neutral baseline; all Páramo scenarios return T (always-empty defeaters at root → always T), which is the correct baseline showing what DDG adds.

**`Position_framework`** — structural context without external deps

Same as Dung, but agents with `id > 5` are treated as "deeper in contradiction" and generate territorial defeaters. A structural proxy when chuaque is unavailable.

**`Chuaque_framework`** — full paraconsistent evaluation

Delegates to the Python `chuaque` module via `Chuaque_ffi`. Falls back gracefully to N if unavailable. Implements Rescher-Manor argument weighting; returns genuine B for dialetheic conflicts.

**`Make_paramo_framework`** — position × claim_type matrix

The primary framework for Páramo research. Takes a `Ctx` functor providing `position_of : Agent_id.t -> epistemic_position option`.

### The Position × Claim_type Matrix

The framework classifies each argument's claim into a `claim_type`:

```ocaml
type claim_type =
  | Territorial_autonomy       (* "territorial", "autonomy", "land rights" *)
  | Ecosystem_services         (* "ecosystem service", "environmental service" *)
  | Development_policy         (* "development", "economic growth" *)
  | Water_regulation           (* "water regulation", "hydrological" *)
  | Biodiversity_conservation  (* "biodiversity", "conservation" *)
  | Unknown_claim
```

The evaluation matrix encodes **structural contradictions documented in Afanador (2019)**:

| Epistemic position | Territorial_autonomy | Ecosystem_services | Development_policy | Water/Bio |
|---|---|---|---|---|
| Paramuno_lifeworld | **T** | **B** ← dialetheia | **F** | T |
| State_administration | **F** | T | T | N |
| Environmental_agency | **F** | T | **B** ← dialetheia | N |
| Scientific_conservation | N | T | N | **T** |

Two cells encode **genuine dialetheia** (direct B encoding, not accumulation):

1. `Paramuno_lifeworld × Ecosystem_services → B`: Paramuno communities empirically depend on páramo water regulation (T) AND reject "ecosystem services" as a colonial framework that commodifies their territory without consent (F). Both propositions are true in different registers. This is the core irreducible contradiction documented in Afanador (2019) arXiv:1911.06367.

2. `Environmental_agency × Development_policy → B`: Environmental agencies hold a contradictory institutional mandate — they are simultaneously required to facilitate "sustainable development" (promote extraction) and protect conservation areas (restrict extraction). Neither can be subordinated to the other without violating the agency's mandate.

**Why direct encoding matters:** Previous versions derived B by accumulation (Paramuno adds 2 defeaters → Dung counts 2G = 2D → B at next hop). This accidentally produced B as a side-effect of counting, not as a named theoretical finding. Direct encoding makes the dialetheia *explicit* and *named* in the code, matching its status in the analysis of Afanador (2019).

---

## Layer 3: Dialectical Topology

`lib/dialectical/dialectical_topology.ml` and `paramo_topology.ml`

The `TOPOLOGY` interface replaces generic `get_neighbors` with three semantically distinct routing queries:

```ocaml
module type TOPOLOGY = sig
  type t
  val get_attackers : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_defenders : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_arbiters  : t -> Agent_id.t -> Argument.t -> Agent_id.t list
end
```

Each function encodes a dialectical relation:

| Function | When used by DDG | Epistemological meaning |
|---|---|---|
| `get_attackers` | `Truth F` | Which agents bear burden of proof against this rejection? |
| `get_defenders` | `Truth T` (optional reinforcement) | Which agents can support this acceptance? |
| `get_arbiters` | `Truth N` | Which agents have epistemic standing to arbitrate? |

**`Fallback_topology`** — all three return direct neighbors (v4 backward-compatible behavior).

**`Simple_dialectical_topology`** — assigns explicit `dialectical_role` to each agent:
```ocaml
type dialectical_role =
  | Attacker_of of string list   (* attacker for claims matching these patterns *)
  | Defender_of of string list
  | Arbiter_of of string list
  | Neutral
```

**`Paramo_topology.Paramo_topology`** — routes based on `epistemic_position` vs claim content:

```ocaml
(* State arguing "ecosystem" → route to Paramuno attackers *)
| Some State_administration
  when String.is_substring arg.claim ~substring:"ecosystem" ->
    List.filter neighbors ~f:(fun n ->
      match position_of t n with Some Paramuno_lifeworld -> true | _ -> false)
```

This ensures routing reflects the structural opposition documented in Afanador (2019), not arbitrary list order.

---

## Layer 4: DDG Protocol

`lib/dialectical/protocol_ddg.ml`

The traversal loop in `Make_DDG`:

```
execute_with_arg:
  1. Framework evaluates arg at root agent
  2. Framework adds any defeaters to arg.defeaters
  3. Match on truth_val:
     - Truth T → terminal (argument accepted)
     - Truth B → terminal (contradiction preserved — KEY FINDING)
     - Truth F → get_attackers → recurse into attacker with highest epistemic position
     - Truth N → get_arbiters → recurse into arbiter
  4. Return dialogue_trace
```

**Why B is terminal:**

DIG/DEC would continue searching for a "better" delegatee when hitting a contradictory state. DDG *stops* and records the B as its finding. The research question is not "what is the optimal outcome?" but "where does the contradiction live?"

```ocaml
type dialogue_trace = {
  argument         : Argument.t;
  final_evaluation : truth_val;
  path             : Agent_id.t list;
  defeaters_found  : string list;
}
```

`execute` runs with a fresh `root_argument()` (generic claim, empty defeaters). `execute_with_arg` accepts a specific pre-built argument (used for Páramo scenarios).

---

## Analysis

`lib/dialectical/analysis.ml`

DDG metrics are **incommensurable** with DIG/DEC metrics. Do not compare PSD or regret to contradiction coverage.

| Metric | What it measures |
|---|---|
| `contradiction_coverage` | Fraction of traces ending in B — DDG's primary metric |
| `mean_argument_depth` | How deep into the network arguments travel before resolution |
| `defeater_diversity` | How many distinct defeater strings the network surfaces |
| `contradiction_hubs` | Which agents appear most often in B-ending traces |

High contradiction coverage with low depth (scenario A: 100%, depth 1) means the contradiction is **immediate and structural** — it surfaces as soon as the argument reaches any Paramuno agent, regardless of topology. This is the strongest form of the finding.

Low contradiction coverage (scenario B: 0%) means the argument is uncontested within its epistemic network — Paramuno framing of territorial autonomy finds no opposition from other Paramuno agents.

---

## Extending DDG

### New territorial case study

1. Create `My_topology.ml` implementing `TOPOLOGY` with epistemically justified routing
2. Create or extend `My_framework` implementing `FRAMEWORK` with a position × claim_type matrix
3. Define relevant `Argument.t` constructors in `argument.ml`
4. Instantiate: `module DDG = Protocol_ddg.Make_DDG(My_topology)(My_framework)`

### New evaluation backend

Implement `FRAMEWORK` with your logic:

```ocaml
module My_framework : FRAMEWORK = struct
  let evaluate ~agent_id ~arg = ...  (* return truth_val *)
  let find_defeaters ~agent_id ~arg = ...  (* return string list *)
end
```

If your backend requires external state (topology, database, network), pass it via a closure in a `Ctx` functor following the `Make_paramo_framework` pattern.

### Chuaque integration

`Chuaque_ffi.is_available ()` checks at runtime whether the Python module is reachable. `Chuaque_framework` falls back to N on any FFI error. To extend:

1. Extend `Chuaque_ffi.evaluate_argument` to parse richer JSON responses
2. Add `Chuaque_ffi.query_weighted_defeaters` for Rescher-Manor weights
3. Use `Chuaque_framework` as the default when available (already done in `dialectical_example.ml`)
