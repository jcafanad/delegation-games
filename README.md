# Delegation Games: Coalitional and Dialectical Algorithms

OCaml implementation of recursive delegation protocols modeling hierarchical extraction and cooperative resistance.

## Theoretical Foundations

This repository implements algorithms from:
- Afanador, J., Oren, N., & Baptista, M. S. (2019). "A Coalitional Algorithm for Recursive Delegation." *PRIMA 2019*.
- Afanador, J. (2019). "Recursive Delegation and a Trust-Measuring Algorithm." PhD Thesis, University of Aberdeen.

The code operationalizes a critical analysis of delegation as simultaneously:
1. **Hierarchical extraction** (DIG): delegation chains model how value flows upward through institutional hierarchies
2. **Coalitional resistance** (DEC): cooperation enables sustainability under material constraints
3. **Dialectical refusal** (DDG): contradictory positions (accepting/rejecting delegation) preserved rather than resolved

### Theoretical Trajectory

**DIG → DEC → DDG** represents increasing theoretical sophistication:

- **DIG** (Delegation as Iterative Game): Models delegation via quitting games. Agents compute mixed strategies to approximate ε-equilibria. Value allocation formula $v_i = (i+1)V/T_n$ encodes hierarchical positioning — agents deeper in hierarchy have higher *potential* to generate value but rewards flow inversely via $r_i = i \cdot o_k / H_k$. This formalizes surplus extraction: development discourse promises value to periphery while accumulation concentrates at center.

- **DEC** (Delegation as Coalitional): Models cooperation via Shapley/Myerson values. Agents form coalitions to maximize collective welfare under resource constraints. More sustainable than DIG (longer operation under same budget) but potentially lower individual rewards. Encodes cooperative resistance — communities achieve less "development" (measured by extractive metrics) but sustain longer.

- **DDG** (Delegation as Dialectical): Preserves contradictions rather than forcing resolution. Arguments (claim + grounds + defeaters) traverse the delegation network; each agent evaluates via Belnap four-valued logic (T/F/B/N). The B state (contradictory: both T and F) is a valid, terminal finding — not a failure requiring convergence. Integrates with `chuaque` paraconsistent logic via FFI.

## Empirical Grounding

Fieldwork with Paramuno communities in Colombian Páramo ecosystems informs the theoretical architecture. Territorial disputes with State actors and extractive industries create contradictory demands:
- State/capital delegate "development" projects (extraction disguised as aid)
- Communities must simultaneously resist dispossession AND engage institutions
- Cannot simply accept or reject — must navigate contradictory position

DEC models coalitional forms of resistance under constraint. DDG makes the dialetheic position explicit: Paramuno communities accept that the páramo provides water regulation (T) AND reject the "ecosystem services" framework that commodifies their territory (F). The B state encodes this irreducible contradiction.

## Architecture

### Module Hierarchy

```
delegation-games/
├── lib/
│   ├── core_types.ml              - Fundamental types (agents, values, chains, equilibria)
│   ├── agent.ml                   - Agent state and learning mechanisms
│   ├── belnap.ml                  - Four-valued logic: T | F | B | N (simple)
│   ├── belnap_gadt.ml             - Four-valued logic via GADT (type-safe, Phase 2)
│   ├── semantic_types.ml          - Shared semantic primitives
│   ├── coalition.ml               - Characteristic functions, Shapley/Myerson values
│   ├── formation.ml               - Coalition formation via myopic lookahead
│   ├── protocol_effects.ml        - Effect interface shared across protocols
│   ├── protocol_dig.ml            - DIG: quitting games
│   ├── protocol_dec.ml            - DEC: coalitional games
│   ├── chuaque_ffi.ml             - Python chuaque module FFI (subprocess/JSON)
│   ├── chuaque_interface.ml       - Type-safe chuaque interface
│   ├── dialogue_effects.ml        - Callback-based referee (OCaml 4/5 compatible)
│   ├── simulation.ml              - Experimental harness (DIG/DEC)
│   └── dialectical/
│       ├── argument.ml            - Argument type: claim + grounds + defeaters
│       ├── argumentation_framework.ml - Evaluation backends (Dung, Position, Chuaque, Paramo)
│       ├── dialectical_topology.ml    - Topology interface + Simple/Fallback implementations
│       ├── paramo_topology.ml         - Páramo epistemic position topology
│       ├── protocol_ddg.ml            - DDG: dialectical delegation preserving B states
│       └── analysis.ml                - DDG-specific metrics (incommensurable with DIG/DEC)
├── bin/
│   ├── example.ml                 - DIG vs DEC experiment
│   └── dialectical_example.ml     - DDG experiment with Páramo scenarios
└── docs/
    ├── DDG_ARCHITECTURE.md        - DDG sublibrary design and rationale
    └── PARAMO_EXPERIMENT.md       - Páramo experiment findings
```

### Key Design Decisions

**1. Value Allocation as Hierarchical Positioning**

```ocaml
let allocate ~game_value ~depth ~hierarchy_size =
  let d = Float.of_int depth in
  let t_n = triangular hierarchy_size in
  (d +. 1.) *. game_value /. t_n
```

Agents farther from root receive higher allocations — they're positioned to "develop." But rewards flow inversely:

```ocaml
let distribute_reward ~outcome ~position ~coalition_size =
  let h_k = harmonic coalition_size in
  (Float.of_int position) *. outcome /. h_k
```

Closer to root = larger share. Encodes extraction: periphery generates, center captures.

**2. Resource Constraints as Material Limits**

```ocaml
type budget = float
let consumption_rate ~successes ~failures =
  1. /. Float.of_int (successes + failures)
```

Each delegation consumes resources inversely proportional to trust. Well-known relationships cost less. DEC's cooperative efficiency emerges from *learning* to delegate effectively, reducing resource burn.

**3. Coalition Formation as Myopic Agency**

```ocaml
let sample_length t =
  t.min_length + Random.int (t.max_length - t.min_length + 1)
  (* max_length = 3: theoretical commitment to bounded rationality *)
```

Agents can only foresee 2-3 hops ahead. Not a computational limitation — an ontological claim about the locality of agency. Global optimization requires *cooperation* to pool local knowledge.

**4. Belnap Four-Valued Logic for Contradictions**

```ocaml
type 'a truth =
  | T : bool truth    (* accepted *)
  | F : bool truth    (* rejected *)
  | B : unit truth    (* contradictory — preserved, not resolved *)
  | N : unit truth    (* unknown — insufficient information *)
```

The GADT encoding (Phase 2) makes it impossible to treat B as a failure state. `ex_contradictione_quodlibet` is explicitly blocked — from B you cannot derive T or F without additional evidence.

**5. Dialectical Routing: Topology as Epistemic Map**

```ocaml
module type TOPOLOGY = sig
  type t
  val get_attackers : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_defenders : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_arbiters  : t -> Agent_id.t -> Argument.t -> Agent_id.t list
end
```

DDG routes based on evaluation outcome:
- `Truth F` → `get_attackers` (burden of proof: who can challenge this rejection?)
- `Truth N` → `get_arbiters` (epistemic standing: who has relevant expertise?)
- `Truth T | Truth B` → terminal (accepted or contradiction preserved)

## Usage

### Installation

Requires OCaml >= 4.14:

```bash
opam install dune core core_unix owl ppx_jane
cd delegation-games
dune build
```

### Running Experiments

**DIG vs DEC comparison:**
```bash
dune exec delegation-example
```

Compares hierarchical (DIG) vs coalitional (DEC) protocols on directed tree topology. Reports PSD, mean reward, regret.

**DDG dialectical experiment:**
```bash
dune exec dialectical-example
```

Runs three argumentation frameworks on tree topology, then the full Páramo experiment with three scenarios. Reports contradiction coverage, mean argument depth, defeater diversity.

**With chuaque (paraconsistent logic):**
```bash
export PYTHONPATH=/path/to/contra-value:$PYTHONPATH
dune exec dialectical-example
```

If chuaque is available, DDG will use it as the evaluation backend. Falls back to `Position_framework` if unavailable.

### Programmatic API — DIG/DEC

```ocaml
open Delegation_games

let registry =
  Simulation.Simulation.create_registry
    ~topology_spec:(Simulation.Sim_params.Directed_tree { levels = 4; branching = 5 })
    ~game_value:1000.

let params = Map.of_alist_exn (module String) [
  ("max_coalition_length", "3");
  ("adaptive_coalitions", "false");
] in

let dec = Protocol_dec.DEC.create ~registry ~params in
let (chain, reward, equilibrium) = Protocol_dec.DEC.execute dec ~budget:500. in

match equilibrium with
| Equilibrium.Resolved r ->
    printf "Resolved: reward=%.2f, strategy=%.3f\n" r.reward r.strategy
| Equilibrium.Oscillating o ->
    printf "Oscillating: period=%d\n" o.period
| _ -> ()
```

### Programmatic API — DDG

```ocaml
open Delegation_games
open Dialectical

(* Build Páramo topology with epistemic position assignments *)
let registry = Simulation.Simulation.create_registry
  ~topology_spec:(Simulation.Sim_params.Directed_tree { levels = 3; branching = 3 })
  ~game_value:1000.

let ptopo = Paramo_topology.Paramo_topology.create ~base_topology:registry in
Paramo_topology.Paramo_topology.assign_position ptopo (Agent_id.of_int 0)
  Paramo_topology.Paramuno_lifeworld;
(* ... assign remaining agents ... *)

(* Instantiate position-aware framework *)
let module PF = Argumentation_framework.Make_paramo_framework(struct
  let position_of id = Paramo_topology.Paramo_topology.position_of ptopo id
end) in

(* Instantiate DDG with Páramo topology and framework *)
let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in

(* Run with specific argument *)
let trace = DDG.execute_with_arg
  ~topology:ptopo
  ~root_agent:Agent_id.root
  ~arg:(Argument.paramo_ecosystem_argument ())
in

match trace.Protocol_ddg.final_evaluation with
| Belnap_gadt.Truth Belnap_gadt.B ->
    printf "Contradiction found: %s\n"
      (String.concat ~sep:"; " trace.Protocol_ddg.defeaters_found)
| _ -> ()
```

## Integration with Paraconsistent Logic (chuaque)

`chuaque_ffi.ml` implements a subprocess-based FFI: arguments are serialized to JSON and sent to a Python chuaque process; responses are parsed back to `truth_val`.

```ocaml
(* Check availability at runtime *)
if Chuaque_ffi.is_available () then
  (* use Chuaque_framework *)
else
  (* fall back to Position_framework *)

(* Direct usage *)
let json_input = Argument.to_json arg in
match Chuaque_ffi.evaluate_argument json_input with
| Some "B" -> Truth B  (* paraconsistent contradiction confirmed *)
| Some "T" -> Truth T
| _        -> Truth N
```

To enable: set `PYTHONPATH` to include the `contra-value` directory containing the `chuaque` module.

## Theoretical Commitments Encoded in Type System

1. **Hierarchical extraction is structural, not individual**
   - `Value.allocation` depends on `depth` in hierarchy, not agent capabilities
   - Rewards flow inversely via `distribute_reward` — position determines capture

2. **Cooperation is ontologically prior to agency**
   - `Characteristic_function` maps coalitions (not individuals) to values
   - `Shapley.value` computes individual contributions *from* collective
   - Agents are constituted by coalitional positioning, not reducible to it

3. **Contradictions are real, not errors**
   - `Truth B` is a valid terminal state (not "failed to converge")
   - `Oscillating` equilibria preserved rather than averaged out
   - DDG treats `Execute AND Delegate` as a first-class dialetheic action

4. **Agency is fundamentally local and bounded**
   - Coalition formation limited to 3 hops (myopic horizon)
   - No global optimization — agents cooperate to *approximate* global structure
   - Decentralized learning converges to shared understanding

5. **DDG metrics are incommensurable with DIG/DEC metrics**
   - DIG/DEC ask: "How efficiently does delegation optimize value extraction?"
   - DDG asks: "Which structural contradictions does optimization make invisible?"
   - Contradiction coverage, argument depth, and defeater diversity cannot be compared to PSD or regret

## Empirical Results

### DIG vs DEC (paper replication)

| Metric | DIG | DEC |
|---|---|---|
| Mean reward | ~435 | ~355 |
| Budget longevity | ~150 trials | ~200 trials |
| Regret | ~4.4 | ~10.3 |

Interpretation: DEC sacrifices individual extractive efficiency for sustainability. Higher regret reflects cooperation sacrificing "development" for collective welfare.

### DDG Páramo Experiment

Three scenarios with root agent assigned `Paramuno_lifeworld`, level-1 agents `Environmental_agency`:

| Scenario | Claim | Root eval | Final | Depth | B-rate |
|---|---|---|---|---|---|
| A: Ecosystem services | "ecosystem services framework should govern Páramo commons" | B (dialetheia) | B | 1 hop | 100% |
| B: Territorial autonomy | "territorial autonomy is the legitimate basis for Páramo governance" | T (own framing) | T | 1 hop | 0% |
| C: Development policy | "development projects should proceed in Páramo zone" | F → routes to env. agency → B | B | 2 hops | 100% |

Key finding: the contradiction is **asymmetric**. Paramuno framing (territorial autonomy) is uncontested within their network. State/agency framing (ecosystem services, development) immediately produces B — the contradiction is structural, not accidental.

See `docs/PARAMO_EXPERIMENT.md` for full interpretation.

## Contributing

This is research code operationalizing critical theory. Contributions should engage theoretical commitments:

- Code changes that alter value allocation formulas must justify hierarchical positioning
- Protocol modifications must explain implications for extraction vs cooperation
- DDG development must preserve contradictions rather than resolving them

See `CONTRIBUTING.md` for technical guidelines.

## License

MIT License. See `LICENSE`.

## Citation

If using this code, please cite:

```bibtex
@inproceedings{afanador2019coalitional,
  title={A Coalitional Algorithm for Recursive Delegation},
  author={Afanador, Juan and Oren, Nir and Baptista, Murilo S},
  booktitle={PRIMA 2019: Principles and Practice of Multi-Agent Systems},
  pages={405--422},
  year={2019},
  organization={Springer}
}

@phdthesis{afanador2019recursive,
  title={Recursive Delegation and a Trust-Measuring Algorithm},
  author={Afanador, Juan},
  year={2019},
  school={University of Aberdeen}
}
```

## Contact

Juan Afanador - [GitHub](https://github.com/afanador)

## Acknowledgments

Fieldwork conducted with Paramuno communities in Colombian Páramo ecosystems. Theoretical framework draws on Adorno's negative dialectics and value-dissociation critique. Paraconsistent logic integration uses the `contra-value` / `chuaque` framework.
