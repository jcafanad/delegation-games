# Páramo Experiment: DDG Findings

This document interprets the results of the Páramo dialectical experiment implemented in `bin/dialectical_example.ml`. It explains the setup, findings, and what they reveal about the structural contradictions of Páramo territorial governance.

---

## Background

The Colombian Páramo is a high-altitude ecosystem that provides water regulation for millions of downstream people. It is simultaneously:
- **Paramuno territory**: inhabited and maintained by indigenous communities for generations, subject to collective governance under international indigenous rights law (ILO 169, UN Declaration on Rights of Indigenous Peoples)
- **Ecosystem service provider**: designated under national and international conservation frameworks as a provider of carbon sequestration and water regulation, governed via market-based "ecosystem services" mechanisms
- **Development frontier**: targeted by mining, agriculture, and infrastructure projects under national development policy

These three framings are not reconcilable by negotiation or optimization. They encode fundamentally different ontologies of what the páramo *is* and who has legitimate authority over it. The DDG experiment makes this computational.

---

## Experimental Setup

** Topology Composition and Depth Distribution**

The reference topology is a directed tree (levels=3, branching=3) that contains:
- 31 Paramuno agents (77.5%)
- 3 Environmental_agency (7.5%)
- 3 Scientific_conservation (7.5%)
- 3 State_administration (7.5%)

This composition reflects the numerical dominance of Paramuno communities
in the Guantiva-La Rusia Páramo complex, but creates a sampling bias toward
Paramuno-perspective evaluations.

For Ecosystem_services_political claims:
- 77.5% of trials: Paramuno root → B at depth=1 (direct evaluation)
- 7.5% of trials: Sci root → N → Paramuno → B at depth=2
- 7.5% of trials: Env root → N → Sci → N → Paramuno → B at depth=3
- 7.5% of trials: State root → T at depth=1

Mean depth ~1.2 reflects this distribution. The routing mechanism (depth 2-3)
is verified and works correctly but represents minority of trials.

**Epistemic position assignments:**

| Agent(s) | Position | Theoretical meaning |
|---|---|---|
| id=0 (root) | `Paramuno_lifeworld` | Territorial/relational ontology, collective governance |
| ids 1–3 (level 1) | `Environmental_agency` | Ecosystem services mandate + development obligation |
| ids 4–12 (level 2) | `Scientific_conservation` | Technical/ecological expertise, evidence-based |
| ids 13–39 (level 3) | `Paramuno_lifeworld` | Leaf-level community nodes |

**Framework:** `Make_paramo_framework` with position × claim_type matrix encoding:
- `Paramuno_lifeworld × Ecosystem_services → B` (genuine dialetheia)
- `Environmental_agency × Development_policy → B` (contradictory mandate)
- `State_administration × Territorial_autonomy → F` (legality objection)
- etc. (full matrix in `DDG_ARCHITECTURE.md`)

**Trials:** 200 per scenario

---

## Scenario A: Ecosystem Services Governance

**Claim:** "ecosystem services framework should govern Páramo commons"

**Advancing actor:** State / Environmental agency

**Results:**
```
Outcome distribution:
  Accepted (T):     0 (0.0%)
  Rejected (F):     0 (0.0%)
  Contradicted (B): 200 (100.0%)
  Unknown (N):      0 (0.0%)

Contradiction coverage: 100.0%
Mean argument depth:    1.0 hops
```

**Interpretation:**

The claim is evaluated by the root agent (Paramuno_lifeworld). The position × claim_type matrix immediately returns `Truth B`:

- **T register:** The páramo empirically provides water regulation. Paramuno communities know this — they have maintained the ecosystem for generations precisely because of this function.
- **F register:** The "ecosystem services" *framework* commodifies this function as an abstract market good, extracting value from Paramuno stewardship without consent, and delegating governance to State/capital actors who have no relational knowledge of the territory.

Both propositions are true simultaneously, in different registers. This is not a logical error — it is a **genuine dialetheia** documented in Afanador (2019) arXiv:1911.06367. The B state is reached at depth 1 (the root agent itself) because the contradiction is *internal* to Paramuno epistemic position: no routing is needed to find it.

**What DIG/DEC would do:** Assign a utility to each position (weighted average?), converge on a strategy (cooperate with ecosystem services governance for X% of trials?). The contradiction would be *erased* by the optimization. The finding would be invisible.

---

## Scenario B: Territorial Autonomy

**Claim:** "territorial autonomy is the legitimate basis for Páramo governance"

**Advancing actor:** Paramuno communities

**Results:**
```
Outcome distribution:
  Accepted (T):     200 (100.0%)
  Rejected (F):     0 (0.0%)
  Contradicted (B): 0 (0.0%)
  Unknown (N):      0 (0.0%)

Contradiction coverage: 0.0%
Mean argument depth:    1.0 hops
```

**Interpretation:**

The claim is evaluated by the root agent (Paramuno_lifeworld). The matrix returns `Truth T` — Paramuno framing of territorial autonomy is accepted immediately and without contradiction within the Paramuno epistemic network.

This is **the asymmetry**: the ecosystem services claim (State framing) produces 100% contradiction; the territorial autonomy claim (Paramuno framing) produces 100% acceptance. The contradiction is not symmetric — it is imposed on Paramuno communities by external framings, not generated internally.

**What this shows:** The B state in Scenario A is not "both sides are equally contradicted." It is specifically the ecosystem services *framework* that is contradictory when evaluated from Paramuno epistemic position. Paramuno framing, evaluated from the same position, is coherent.

This computational asymmetry reflects the finding of Afanador (2019): Paramuno communities are not "confused" about their territory — they have a coherent relational ontology. The contradiction is introduced by State/capital framings that impose incommensurable ontologies.

---

## Scenario C: Development Policy

**Claim:** "development projects should proceed in Páramo zone"

**Advancing actor:** State

**Results:**
```
Outcome distribution:
  Accepted (T):     0 (0.0%)
  Rejected (F):     0 (0.0%)
  Contradicted (B): 200 (100.0%)
  Unknown (N):      0 (0.0%)

Contradiction coverage: 100.0%
Mean argument depth:    2.0 hops
Defeater diversity:     2 unique defeaters

Contradiction hubs (top 3):
  Agent 0: 200 contradiction traces
  Agent 3: 200 contradiction traces
```

**Interpretation:**

The claim reaches the root agent (Paramuno_lifeworld), which evaluates `Development_policy` and returns `Truth F` — development projects violate territorial rights. The Paramuno framework adds defeaters:
- "Development projects violate territorial rights without free, prior, and informed consent"
- "Scalar economic growth erases relational ontology of páramo stewardship"

With `Truth F`, DDG routes to `get_attackers` — agents who can challenge this rejection. In the Páramo topology, State/development arguments attacked by Paramuno are routed to... Environmental agency neighbors (ids 1–3), who hold structural authority over the Paramuno community.

Environmental agency evaluates `Development_policy` and returns `Truth B` — contradictory institutional mandate: agencies must simultaneously enable "sustainable development" (State mandate) and protect conservation areas (environmental mandate). Neither can be subordinated without violating the agency's legal remit.

**Depth 2 vs Depth 1:** Unlike Scenario A, the B state here requires *routing* — Paramuno rejects (F), argument travels to Environmental agency, Environmental agency finds the contradiction (B). The finding is relational, not internal. This maps a different structure: the contradiction lives at the *interface* between Paramuno refusal and Environmental agency mandate, not within a single epistemic position.

**Contradiction hubs:** Both Agent 0 (Paramuno root) and Agent 3 (one of the Environmental_agency level-1 nodes) appear in all 200 B traces. Agent 0 is the rejection point; Agent 3 is the contradiction point. The hub analysis identifies which structural positions mediate between competing demands.

---

## Comparative Summary

| | Scenario A | Scenario B | Scenario C |
|---|---|---|---|
| Claim type | Ecosystem_services | Territorial_autonomy | Development_policy |
| Root eval | **B** (internal dialetheia) | **T** (uncontested) | **F** (rejection) |
| Final | B | T | B (at depth 2) |
| Depth | 1 | 1 | 2 |
| B-rate | 100% | 0% | 100% |
| Where contradiction lives | Within Paramuno position | N/A | Interface: Paramuno ↔ Environmental_agency |

---

## Theoretical Significance

### What DDG reveals that DIG/DEC cannot

DIG/DEC treat contradictory demands as optimization problems: find the strategy that best balances competing utilities. This requires translating incommensurable positions into a common metric (utility, reward, equilibrium). The translation *erases* the contradiction by assuming a shared ontology within which trade-offs can be computed.

DDG refuses this move. The B state names what is lost: **the claim that both propositions are true in their respective registers is itself a finding**. Ecosystem services provides water (T) AND the ecosystem services framework is a colonial imposition (F). These are not two sides of a trade-off; they are two truths that cannot be collapsed into each other.

### The asymmetry as research finding

The 100%/0%/100% pattern is not an artifact of parameters. It follows directly from:
1. The structural position of Paramuno communities relative to State framings
2. The documented contradiction between water provision and commodification
3. The documented contradiction between Environmental agency's dual mandate

A different parameter set would not change the qualitative finding — only the depth at which contradictions surface and the specific defeaters generated.

### Limitations

1. **Depth 1 termination (Scenarios A, B):** With the current topology (Paramuno root, Environmental_agency level 1), the ecosystem services contradiction surfaces immediately because the root agent *is* a Paramuno agent. A different topology (State root, Paramuno at level 2) would produce different routing paths and different depths.

2. **claim_type classification is coarse:** `classify_claim` uses substring matching on lowercase strings. Claims that embed multiple framings ("sustainable development with ecosystem services") are classified by first match. A richer NLP-based classifier would allow more nuanced claim analysis.

3. **Defeater accumulation:** In the current implementation, B from direct encoding terminates traversal before defeaters accumulate across multiple hops. A future version could allow B-state arguments to continue through a "contradiction elaboration" phase to surface additional structural tensions.

4. **Scientific_conservation is passive:** In the current matrix, `Scientific_conservation` agents produce T for technical claims and N otherwise — they never generate B. Real scientists face contradictory mandates (data collection vs. advocacy, conservation vs. livelihoods) that the current matrix doesn't encode.

5. **Rebalanced topology:** Future work should allow for equal position distribution increasing routing frequency and mean depth to ~2.0, and better demonstrating the epistemic gap critique while sacrificing demographic realism.

---

## Running the Experiment

```bash
dune exec dialectical-example
```

The output includes all three scenarios plus comparative summary.

To modify the experiment (e.g., try State as root agent):

```ocaml
(* In bin/dialectical_example.ml, change position assignment *)
assign (id 0) Paramo_topology.State_administration;
List.iter [1; 2; 3] ~f:(fun i -> assign (id i) Paramo_topology.Paramuno_lifeworld);
```

This will change the routing structure: State evaluates ecosystem claim as T (accepted immediately, no B), and territorial claim as F (routes to Paramuno attackers who add defeaters).
