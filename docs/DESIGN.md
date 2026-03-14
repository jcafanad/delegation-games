# Design Document: Delegation Games

## Architecture Overview

This codebase makes theoretical commitments *computationally legible* through:

1. **Type system**: Encodes distinctions between hierarchical/coalitional/dialectical delegation
2. **Module hierarchy**: Reflects separation between value (extraction logic) and cooperation (resistance logic)
3. **Functors**: Abstract over topologies and frameworks while preserving theoretical commitments
4. **Effect preservation**: Oscillations and contradictions are first-class, not errors

## Module Architecture

```
                  ┌──────────────┐
                  │ core_types   │
                  │ (ontology)   │
                  └──────┬───────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │ agent   │    │coalition│    │formation│
    │(learning)│   │(Shapley)│    │(myopic) │
    └────┬────┘    └────┬────┘    └────┬────┘
         │               │               │
         └───────────────┼───────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │protocol │    │protocol │    │protocol │
    │  _dig   │    │  _dec   │    │  _ddg   │
    │(quitting)│   │(coalit.)│    │(dialec.)│
    └────┬────┘    └────┬────┘    └────┬────┘
         │               │               │
         │               │         ┌─────▼──────────────────────┐
         │               │         │ lib/dialectical/            │
         │               │         │ - argument.ml               │
         │               │         │ - argumentation_framework.ml│
         │               │         │ - dialectical_topology.ml   │
         │               │         │ - paramo_topology.ml        │
         │               │         │ - analysis.ml               │
         │               │         └─────────────────────────────┘
         └───────────────┼───────────────┘
                         │
                   ┌─────▼─────┐
                   │simulation │
                   │(empirical)│
                   └───────────┘
```

## Core Type System

### Theoretical Distinctions Encoded

**1. Value vs Reward**

```ocaml
type allocation = float  (* potential to generate value *)
type reward = float      (* realized accumulation *)
```

Not synonyms. `allocation` reflects *position* in hierarchy (depth). `reward` reflects *actual capture* from delegation outcomes. This encodes extraction: periphery has high allocation (positioned to "develop") but low rewards (surplus extracted).

**2. Equilibrium States**

```ocaml
type t =
  | Resolved of resolved       (* classical: converged strategy *)
  | Oscillating of oscillating (* cyclic: unresolved contradiction *)
  | Undecided                  (* dialetheic: both simultaneously *)
```

Classical game theory has only `Resolved`. We add `Oscillating` (detected pattern) and `Undecided` (genuine contradiction). This makes oscillations *legitimate* rather than failures.

**3. Actions**

```ocaml
type t =
  | Execute
  | Delegate of Agent_id.t
  | Reject
```

In DIG/DEC: mutually exclusive. In DDG: can be contradictory (Execute AND Delegate). The dialetheic position is encoded at the evaluation layer via `Truth B` rather than at the action layer directly.

**4. Belnap Four-Valued Logic**

Two encodings coexist:

`belnap.ml` (simple, for interop):
```ocaml
type t = T | F | B | N
```

`belnap_gadt.ml` (Phase 2, type-safe):
```ocaml
type _ truth =
  | T : bool truth
  | F : bool truth
  | B : unit truth   (* no type variable — cannot derive T or F from B *)
  | N : unit truth
```

The GADT encoding makes `ex_contradictione_quodlibet` impossible at the type level. `Truth B` cannot be pattern-matched as a `bool truth`, so no code can accidentally treat it as T or F. This is the type-system analog of paraconsistency.

## Value Allocation: Encoding Hierarchical Extraction

### Formula Derivation

```ocaml
let allocate ~game_value ~depth ~hierarchy_size =
  let d = Float.of_int depth in
  let t_n = triangular hierarchy_size in  (* n(n+1)/2 *)
  (d +. 1.) *. game_value /. t_n
```

**Why triangular numbers?**

For uniform branching, total agents up to depth D approximates triangular series. Allocation formula ensures:
- `Σ allocations = V` (total value conserved)
- `allocation[d] > allocation[d-1]` (deeper = more potential)

**Theoretical interpretation:** Peripheral agents are *positioned* for value generation (sensors in network, farmers in supply chain, workers in production). Center captures without generating (management, finance, State).

### Reward Distribution: Inverse Flow

```ocaml
let distribute_reward ~outcome ~position ~coalition_size =
  let h_k = harmonic coalition_size in  (* Σ(1/i) *)
  (Float.of_int position) *. outcome /. h_k
```

Harmonic series ensures:
- `Σ rewards = outcome` (value conserved)
- `reward[1] > reward[2] > ... > reward[n]` (closer to root captures more)

**Theoretical interpretation:** Value *flows upward*. Models hierarchical rent extraction, unequal exchange in global value chains, surplus accumulation at imperial centers.

## Coalition Formation: Myopic Horizon as Ontology

### Bounded Rationality

```ocaml
let default = {
  min_length = 2;
  max_length = 3;
  adaptive = false;
}
```

**Why max=3?** Not computational constraint — *theoretical commitment*. Agents cannot foresee entire delegation chain. They know themselves, immediate neighbors, neighbors' neighbors. This is *constitutive* of agency. Global optimization requires cooperation to pool local knowledge.

### Adaptive Coalitions

```ocaml
let adaptive_length t ~remaining_budget ~initial_budget =
  if not t.adaptive then sample_length t
  else
    let budget_ratio = remaining_budget /. initial_budget in
    if Float.(budget_ratio < 0.3) then
      t.min_length  (* conserve resources when depleted *)
```

When enabled: coalition size shrinks as resources deplete. Models *learning under constraint* — communities reduce overhead as material conditions worsen.

## Protocol Separation: DIG vs DEC vs DDG

### Shared Interface (DIG/DEC)

```ocaml
module type PROTOCOL = sig
  val decide  : t -> agent:Agent.t -> budget:Resource.budget -> (Action.t * t)
  val learn   : t -> chain:Delegation_chain.t -> outcome:Value.reward -> t
  val execute : t -> budget:Resource.budget -> (Delegation_chain.t * Value.reward * Equilibrium.t)
end
```

**DIG.decide:** Computes quitting game strategies; selects via `argmax(expected_reward)`; checks ε-equilibrium condition.

**DEC.decide:** Forms alternative coalitions; computes Shapley/Myerson values; selects via `argmax(marginal_contribution)`.

### DDG Interface (different payload, different question)

```ocaml
module type DDG = sig
  val execute          : topology:Topo.t -> root_agent:Agent_id.t -> dialogue_trace
  val execute_with_arg : topology:Topo.t -> root_agent:Agent_id.t -> arg:Argument.t -> dialogue_trace
end

type dialogue_trace = {
  argument         : Argument.t;
  final_evaluation : truth_val;
  path             : Agent_id.t list;
  defeaters_found  : string list;
}
```

DDG returns a `dialogue_trace`, not `(chain, reward, equilibrium)`. There is no reward. The terminal value is a Belnap truth value. `Truth B` is a valid, terminal, successful finding — not suboptimal.

### Why Separate Modules?

Could have single `Protocol` with `mode` parameter. Rejected because:

1. **Theoretical distinctness**: DIG, DEC, DDG are *different models* of delegation, not parameter variations
2. **Type safety**: DIG doesn't need `Argument.t`; DDG doesn't need `Value.reward`
3. **Incommensurability**: DDG metrics (contradiction coverage, argument depth, defeater diversity) cannot be compared to DIG/DEC metrics (PSD, regret, E/R)

## DDG Architecture: Four Layers

DDG (`lib/dialectical/`) decomposes into four independently swappable layers:

```
Protocol (Make_DDG functor)
  → uses Topology (TOPOLOGY sig) + Framework (FRAMEWORK sig)
       → both operate on Argument.t
```

See `docs/DDG_ARCHITECTURE.md` for full documentation.

### The FRAMEWORK Interface

```ocaml
module type FRAMEWORK = sig
  val evaluate       : agent_id:Agent_id.t -> arg:Argument.t -> truth_val
  val find_defeaters : agent_id:Agent_id.t -> arg:Argument.t -> string list
end
```

Evaluation is per-agent: the same argument evaluated by a Paramuno agent and a State agent should return different truth values. This is the core of dialectical evaluation — truth is positional, not universal.

### The TOPOLOGY Interface

```ocaml
module type TOPOLOGY = sig
  type t
  val get_attackers : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_defenders : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_arbiters  : t -> Agent_id.t -> Argument.t -> Agent_id.t list
end
```

Routing is semantically loaded: different evaluation outcomes route to different agent types. `Truth F` routes to attackers (who can challenge the rejection); `Truth N` routes to arbiters (who have epistemic standing). This replaces generic `get_neighbors` with dialectically meaningful routing.

### The Make_paramo_framework Functor

`Make_paramo_framework` takes a `Ctx` providing `position_of` and returns a `FRAMEWORK`:

```ocaml
module Make_paramo_framework
    (Ctx : sig
       val position_of : Agent_id.t -> Paramo_topology.epistemic_position option
     end)
: FRAMEWORK
```

Internally, it classifies claims into a `claim_type` ADT and applies a `position × claim_type → truth_val` matrix. Two cells encode genuine dialetheia (direct B encoding):

- `Paramuno_lifeworld × Ecosystem_services → B`
- `Environmental_agency × Development_policy → B`

These are not accidents of counting — they are named theoretical findings.

## Simulation Harness: Replicating Empirical Setup

### Paper Parameters (DIG/DEC)

```ocaml
let paper_default = {
  topology = Directed_tree { levels = 4; branching = 5 };
  num_trials = 1000;
  num_runs = 100;
  budget_range = (500., 800.);
  value_range = (800., 1000.);
}
```

- **156 agents**: 4-level tree with branching=5 → 1+5+25+125 = 156
- **1000 trials**: sufficient for stable reward distributions
- **Budget [500,800]**: allows ~100-200 delegations before exhaustion
- **Value [800,1000]**: higher than budget (scarcity — can't just buy value)

### DDG Experiment Parameters

```ocaml
let n_trials = 200 in
let topology_spec = Directed_tree { levels = 3; branching = 3 }
(* 40 agents: 1 + 3 + 9 + 27 = 40 *)
```

Smaller topology than DIG/DEC because DDG terminates early (at B states, often depth 1-2). More trials would not change the qualitative finding — contradiction coverage converges quickly.

### Metrics (DIG/DEC)

**PSD (Probability of Successful Delegation):**

```ocaml
let compute_psd trials =
  let successes = List.count trials ~f:(fun t -> t.successful) in
  Float.of_int successes /. Float.of_int (List.length trials)
```

*Interpretation:* How often delegation chain reaches execution without resource depletion.

**E/R (Expenditure/Reward Ratio):**

```ocaml
let expenditure_reward_ratio =
  total_expenditure /. (mean_reward *. num_trials)
```

*Interpretation:* Resource cost per unit value generated. DEC should have better E/R than DIG (cooperative efficiency).

**Regret:**

```ocaml
let compute_regret trials ~game_value =
  List.sum (module Float) trials ~f:(fun t -> game_value -. t.reward)
```

*Interpretation:* Cumulative distance from optimal. Note: "optimal" is extractive optimum. DEC may have higher individual regret but better *collective* outcomes.

### Metrics (DDG) — incommensurable with above

**Contradiction coverage:** Fraction of traces ending in B — DDG's primary metric.

**Mean argument depth:** How deep into the network arguments travel. Shallow = contradictions are immediate and structural. Deep = contradictions require deliberation to surface.

**Defeater diversity:** Number of distinct defeater strings the network surfaces. Measures richness of the contradiction space.

**Contradiction hubs:** Which agents appear most often in B-ending traces. Identifies structurally positioned mediators between competing demands.

## Integration Points for Chuaque

### Current Implementation

`chuaque_ffi.ml` implements a subprocess-based FFI:

```ocaml
(* Check availability *)
let is_available () : bool =
  match Sys.getenv_opt "PYTHONPATH" with
  | None -> false
  | Some _ -> (* attempt subprocess call *)

(* Evaluate argument *)
let evaluate_argument (json_input : string) : string option =
  (* spawn Python process, send JSON, parse response *)

(* Query defeaters *)
let query_defeaters ~claim ~grounds : string list option =
  (* paraconsistent defeater discovery *)
```

`chuaque_interface.ml` provides a type-safe wrapper converting between OCaml types and JSON.

### FFI Design Choices

- **Subprocess over ctypes/pyml**: avoids GIL and import complexity; each call is independent; clean failure modes (process exits, no segfault)
- **JSON over binary**: human-readable debugging; no shared memory concerns; chuaque already speaks JSON
- **Graceful degradation**: any FFI failure returns `None`, which maps to `Truth N` — never crashes DDG

### To enable chuaque

```bash
export PYTHONPATH=/path/to/contra-value:$PYTHONPATH
dune exec dialectical-example
```

The experiment automatically detects and uses chuaque when available.

## Performance Considerations

### Why OCaml?

- Fast (compiled, efficient GC)
- Strong types catch theoretical errors at compile-time
- Module system perfect for protocol separation
- Functors enable topology and framework abstraction
- OCaml 5.x Domains will enable genuine parallelism when needed

### Computational Complexity

**DIG:** O(d × n) per trial — linear in depth × branching.

**DEC:** O(k × n × 2^m) per trial — k coalition alternatives, 2^m Shapley computation for m ≤ 3. Effectively O(n) with constant factor ~40.

**DDG:** O(d) per trial — terminates at first B state (often depth 1-2). Faster than DIG/DEC per trial; topology traversal dominates.

## Future Extensions

### 1. Spatial Topology

Embed agents in ℝ² with distance-based cooperation costs.

```ocaml
type spatial_position = { x: float; y: float }
let cooperation_cost ~pos1 ~pos2 = (* Euclidean distance *) ...
```

*Theoretical motivation:* Paramuno communities are geographically constrained. Coalition formation costs increase with distance (travel, communication).

### 2. Temporal Claim Evolution

Allow claims to change over time as policy contexts shift.

```ocaml
type timestamped_claim = { claim: string; epoch: int }
let classify_at_epoch arg epoch = (* time-sensitive classification *)
```

*Theoretical motivation:* "Ecosystem services" as a framing is historically specific (post-1990s). Claims that were once `Unknown_claim` become `Ecosystem_services` as policy language evolves.

### 3. Multi-Claim Arguments

Allow arguments to carry multiple simultaneous claims.

*Theoretical motivation:* Real Páramo governance disputes involve multiple overlapping framings simultaneously — the "sustainable development" discourse combines `Ecosystem_services` AND `Development_policy` in a way that is itself contradictory.

### 4. Institutional Memory Decay

Older coalitions decay, requiring re-exploration.

```ocaml
let decay ~current_time ~entry =
  entry.value *. Float.exp (-. decay_rate *. Float.of_int (current_time - entry.timestamp))
```

*Theoretical motivation:* Movements lose institutional knowledge without organizational infrastructure.

### 5. Extended Scientific Position

`Scientific_conservation` currently never generates B. Real scientists face contradictory mandates (publish findings vs. serve conservation, data collection vs. advocacy). Extend matrix to encode this.

## Conclusion

This codebase makes theory *executable*. Every design choice — from type definitions to module boundaries to the position × claim_type matrix — encodes commitments about:

- How hierarchies extract value (DIG)
- How cooperation enables resistance (DEC)
- How contradictions manifest in delegation, and which framings impose them (DDG)

The DDG additions (Phase 2 onward) make the critical theoretical move explicit in code: replacing optimization over contradictions with a protocol that *names and preserves* them as research findings. The B state is not a bug — it is what the system is designed to find.
