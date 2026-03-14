# Contributing to Delegation Games

This repository implements critical theory through code. Contributions must engage theoretical commitments, not just add features.

## Theoretical Rigor

Every code change encodes theoretical positions about:
- How hierarchies extract value
- How cooperation enables resistance
- How contradictions manifest in social relations

**Before submitting:**
1. Read the paper (Afanador et al., 2019)
2. Understand the theoretical trajectory: DIG → DEC → DDG
3. Explain how your change relates to extraction, cooperation, or contradiction

## Types of Contributions

### 1. Protocol Extensions

**Acceptable:**
- Adaptive coalition length based on learned resource efficiency
- Alternative allocation rules derived from different extraction models
- New equilibrium concepts with dialectical justification

**Not acceptable:**
- "Performance optimizations" that change allocation semantics
- Heuristics without theoretical grounding
- Convergence forcing that eliminates oscillations

**Example good PR:**
```
Title: Add time-decay to hierarchical extraction

Justification: Extraction intensifies under late capitalism. Model via exponentially
increasing allocation to peripheral agents over time, reflecting urgency of
"development" discourse.

Implementation: Modify Value.allocate to accept time parameter, multiply by e^(t/T)
where T is time horizon.

Implications: DIG should show accelerating value flow upward. DEC resistance should
become more costly over time.
```

### 2. DDG Development

DDG is a working implementation. Contributions here require understanding both Belnap semantics and the dialectical routing architecture.

**The four-layer DDG architecture:**
1. `Argument.t` — claim + grounds + mutable defeaters
2. `FRAMEWORK` — position-aware evaluation (returns `truth_val`)
3. `TOPOLOGY` — epistemic routing (attackers / defenders / arbiters)
4. `Make_DDG` functor — traversal loop preserving B states

**Areas open for contribution:**
- New `FRAMEWORK` implementations for other territorial conflicts
- New `TOPOLOGY` implementations (spatial, institutional, temporal)
- Extended `claim_type` classification in `Make_paramo_framework`
- Chuaque FFI improvements (structured responses, batch evaluation)
- Additional DDG analysis metrics in `analysis.ml`

**Requirements:**
- Familiarity with paraconsistent logic (LP, FDE, or Belnap)
- Understanding of dialectical method (Adorno, not Hegel)
- The B state must remain terminal — do not add logic to "resolve" it

**Non-negotiables for DDG:**
- `Truth B` cannot be converted to T or F without new evidence
- `find_defeaters` must not be used to manufacture artificial B states
- Routing decisions (attackers/defenders/arbiters) must be epistemically justified, not arbitrary

### 3. Argumentation Framework Extensions

The `Make_paramo_framework` functor uses a `claim_type` ADT and a position × claim_type matrix. Extensions should follow this pattern:

```ocaml
(* Add a new claim type *)
type claim_type =
  | ...existing...
  | Mining_rights    (* new claim relevant to your case *)

(* Extend classify_claim *)
let classify_claim arg =
  let c = String.lowercase arg.claim in
  if String.is_substring c ~substring:"mining" then Mining_rights
  else ...existing...

(* Add to the evaluation matrix — every position × new_claim pair must be handled *)
| (Paramuno_lifeworld, Mining_rights) -> Truth F
| (State_administration, Mining_rights) -> Truth T
| ...
```

Direct B encoding (genuine dialetheia) is preferred over accumulation-derived B:

```ocaml
(* Preferred: direct encoding *)
| (Environmental_agency, Mining_rights) -> Truth B  (* contradictory mandate *)

(* Avoid: relying on defeater counting to accidentally produce B *)
```

### 4. Empirical Validation

**Acceptable:**
- Replications of paper experiments with different parameters
- Statistical analysis of PSD, E/R, regret distributions
- New Páramo scenarios (different claim types, topology configurations)
- Comparison of DDG outcome distributions across topologies

**Must include:**
- Theoretical prediction before running experiments
- Interpretation connecting results to extraction/cooperation/contradiction dynamics
- For DDG: explanation of which structural contradictions emerge and why

**Not acceptable:**
- "Let's try X and see what happens" without theoretical motivation
- Parameter tuning without justifying new values
- Metrics that don't relate to extraction, cooperation, or contradiction
- Comparing DDG metrics directly to DIG/DEC metrics (they are incommensurable)

### 5. Code Quality

**Standards:**
- OCaml idioms (functors for abstraction, modules for encapsulation)
- Documentation connecting code to theory
- Type signatures that make theoretical commitments explicit

**Module header template:**
```ocaml
(** Module Name — Brief description.

    Theoretical interpretation:
    - What aspect of delegation this models
    - How it relates to extraction/cooperation/contradiction
    - Connection to empirical grounding (if any)

    Implementation notes:
    - Key design decisions and their theoretical justification
    - Limitations and future directions
*)
```

**Function documentation (for value allocation, rewards, dialectical evaluation):**
```ocaml
(** Function description.

    Formula: [mathematical formula if applicable]

    Interpretation: [what this represents theoretically]

    Example: [concrete case with numbers]
*)
```

## Review Process

1. **Theoretical coherence**: Does the change align with critical analysis of hierarchical extraction?

2. **Code quality**: OCaml idioms, clear documentation, type safety?

3. **Empirical grounding**: If relevant, does the change reflect/predict empirical observations?

4. **DDG integrity**: If touching DDG, are B states preserved and routing justified?

## Testing

Tests should verify theoretical properties, not just algorithmic correctness.

**For DIG/DEC — encode structural invariants:**
```ocaml
let%test "value flows upward in hierarchy" =
  (* Root captures more reward than terminal agents *)
  List.hd_exn rewards > List.last_exn rewards

let%test "deeper agents have higher allocation" =
  Agent.allocated_value deep_agent > Agent.allocated_value shallow_agent
```

**For DDG — encode dialectical properties:**
```ocaml
let%test "B state is terminal" =
  (* Once B is reached, traversal must stop *)
  let trace = DDG.execute_with_arg ~arg:(b_producing_arg ()) ... in
  List.length trace.path = 1  (* stopped at first B *)

let%test "ecosystem claim produces B at Paramuno agent" =
  (* Directly encoded in position×claim matrix *)
  let eval = PF.evaluate ~agent_id:paramuno_id ~arg:(paramo_ecosystem_argument ()) in
  phys_equal eval (Truth B)
```

Both structural and algorithmic tests are valuable, but structural tests encode theoretical commitment.

## Non-Negotiables

1. **No convergence forcing in DDG**: Contradictions must be preserved, not resolved
2. **Value allocation must model hierarchy**: Cannot flatten to uniform distribution
3. **Cooperation must differ from competition**: DEC cannot be mere parameter variation of DIG
4. **Types must encode commitments**: Cannot use `float` for values that have structural meaning
5. **DDG metrics are incommensurable with DIG/DEC**: Do not compute PSD or regret for DDG traces

## Example: Good vs Bad Contribution

**Bad PR:**
```
Add caching to Shapley computation for speed.

Caches previously computed marginal contributions to avoid recalculation.
```
❌ No theoretical justification. "Speed" is not a theoretical concern.

**Good PR:**
```
Model memory constraints in coalition formation.

Theoretical motivation: Cooperation requires cognitive overhead — agents must track
partners, outcomes, obligations. Implement bounded memory via LRU cache in
Characteristic_function.

Effect: Older coalitions "forgotten," forcing re-exploration. Models how cooperative
knowledge degrades without institutional support.

Empirical prediction: DEC performance should decline over very long runs as memory
fills. Could model how movements lose institutional memory.
```
✅ Theoretical grounding, structural interpretation, empirical prediction.

**Bad DDG PR:**
```
Resolve B states by averaging grounds and defeaters.
```
❌ B is a research finding, not an error state. Resolving it destroys the theoretical contribution.

**Good DDG PR:**
```
Add State_administration × Ecosystem_services → B case.

Theoretical motivation: State agencies are simultaneously mandated to promote
"ecosystem services" (conservation revenue) AND develop extractive infrastructure.
This is a genuine contradictory mandate, not a policy failure.

Implementation: Extend evaluate_positioned matrix with the new case. Add
corresponding defeaters in find_defeaters.

Prediction: Scenarios with State as root agent evaluating ecosystem claims should
now produce B at depth 1, matching the Environmental_agency pattern.
```
✅ Direct B encoding, empirical grounding, testable prediction.

## Questions?

Open issue tagged `theoretical-question` for conceptual discussions.

For technical OCaml questions, tag `implementation`.

For DDG-specific questions (Belnap semantics, dialectical routing, chuaque FFI), tag `ddg`.

## License

By contributing, you agree to MIT license.

Your code will be used for research that critically analyzes hierarchical structures. If you're uncomfortable with work that challenges State/capital legitimacy, this is not the project for you.
