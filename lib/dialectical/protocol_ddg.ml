(** DDG Protocol — Dialogical Delegation preserving contradictions.

    CRITICAL DIFFERENCE from DIG/DEC:
    ┌─────────────────────────────────────────────────────────────┐
    │ DIG/DEC: optimize scalar utility, escape contradictions     │
    │ DDG:     map argument structure, PRESERVE contradictions    │
    └─────────────────────────────────────────────────────────────┘

    The payload is an Argument.t (claim + grounds + defeaters), not a task.
    The terminal evaluation is Belnap_gadt.truth_val, not float reward.
    Contradiction (B) is a VALID TERMINAL SUCCESS STATE, not suboptimal.

    Theoretical grounding:
    Paramuno communities face contradictions that scalar optimization
    erases. "Accept development revenue" AND "resist territorial
    dispossession" cannot be resolved by weighting — one destroys the
    other. DDG models this by letting the B state stand.

    When deliberation reaches B:
    - DIG/DEC would continue searching for a "better" delegatee
    - DDG STOPS and records the contradiction as its finding

    This is the surgical inversion demanded by epi_critique:
    "Replace Shapley values (reward contribution) with dialectical
     weights (ability to reveal defeaters)."

    Research question changes:
    - NOT: "Is DDG more efficient than DIG?" (incommensurable)
    - BUT: "Does DDG reveal contradictions that DIG erases?"

    References:
    - Dung, P.M. (1995). "On the acceptability of arguments"
    - Lorenzen, P. & Lorenz, K. (1978). "Dialogische Logik"
    - Afanador, J. (2019). Arguing Ecosystem Values with Paraconsistent Logics. arXiv:1911.06367
*)

open Core
open Delegation_games
open Core_types
open Belnap_gadt
open Argument

(** Dialogue trace: complete record of an argument's journey through the network.

    Returned by DDG.execute instead of (chain, reward, equilibrium).
    These fields document WHAT WAS FOUND, not how efficiently.
*)
type dialogue_trace = {
  argument         : Argument.t;       (* the argument, with accumulated defeaters *)
  final_evaluation : truth_val;        (* T/F/B/N — B = contradiction preserved *)
  path             : Agent_id.t list;  (* agents consulted, in order *)
  defeaters_found  : string list;      (* all defeaters registered during traversal *)
}

(** Dialectical topology interface — routing is semantically loaded.

    Unlike generic [get_neighbors], each function encodes a dialectical
    relation that justifies the routing decision:

    - [get_attackers]: agents who can defeat this argument
      Used when F: burden of proof requires substantiation of rejection.
    - [get_defenders]: agents who can support this argument
      Used for robustness checking after T.
    - [get_arbiters]:  agents with epistemic standing on argument's domain
      Used when N: ignorance requires consulting domain experts.

    See [Dialectical_topology] for implementations.
    [Dialectical_topology.Fallback_topology] reproduces v4 behavior.
*)
module type TOPOLOGY = sig
  type t
  val get_attackers : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_defenders : t -> Agent_id.t -> Argument.t -> Agent_id.t list
  val get_arbiters  : t -> Agent_id.t -> Argument.t -> Agent_id.t list
end

(** Build a DDG given a dialectical topology and an argumentation framework.

    Functor parameters:
    - Topo: dialectical topology (attack/defend/arbitrate relations)
    - AF: argumentation framework (evaluate argument, find defeaters)

    The result module provides [execute] which returns [dialogue_trace].
*)
module Make_DDG
    (Topo : TOPOLOGY)
    (AF   : Argumentation_framework.FRAMEWORK)
= struct

  (** Recursive dialogical deliberation.

      Protocol:
      1. Evaluate current argument with AF (from current_agent's perspective)
      2. If T: accepted — terminate, record success
      3. If B: CONTRADICTION — terminate, record contradiction (do NOT escape!)
      4. If F: rejected — AF finds defeaters, add to argument, delegate to neighbor
      5. If N: unknown — delegate to neighbor without adding defeaters

      CRITICAL: Steps 3 vs DIG/DEC behavior:
      - DIG/DEC with B: continue delegating, looking for escape from contradiction
      - DDG with B: STOP. The contradiction is the finding. Preserve it.
  *)
  let rec deliberate ~topology ~current_agent ~arg ~visited =
    let current_path = current_agent :: visited in

    match AF.evaluate ~agent_id:current_agent ~arg with

    | Truth T ->
        (* Accepted — argument stands without defeat *)
        {
          argument         = arg;
          final_evaluation = Truth T;
          path             = List.rev current_path;
          defeaters_found  = arg.defeaters;
        }

    | Truth B ->
        (* CONTRADICTION — this is what DDG is for.
           The argument is BOTH accepted and defeated.
           We PRESERVE this state rather than searching for resolution.

           In Paramuno terms: the contradiction between "develop"
           and "resist" cannot be optimized away. It must be mapped.
        *)
        {
          argument         = arg;
          final_evaluation = Truth B;
          path             = List.rev current_path;
          defeaters_found  = arg.defeaters;
        }

    | Truth F ->
        (* REJECTED — burden of proof: route to agents who can attack this argument.
           The current agent adds defeaters from local knowledge, then delegates
           to a neighbor with relevant attacker role.

           Dialectical justification: rejection must be substantiated. An F
           evaluation without attacker routing is epistemically unsupported.
        *)
        let new_defeaters = AF.find_defeaters ~agent_id:current_agent ~arg in
        List.iter new_defeaters ~f:(Argument.add_defeater arg);

        let attackers = Topo.get_attackers topology current_agent arg in
        let unvisited =
          List.filter attackers ~f:(fun n ->
            not (List.mem visited n ~equal:Agent_id.equal))
        in

        (match unvisited with
         | [] ->
             (* No attackers available — unsupported rejection terminates here *)
             { argument         = arg;
               final_evaluation = Truth F;
               path             = List.rev current_path;
               defeaters_found  = arg.defeaters }
         | attackers_available ->
             (* Randomize selection among qualified attackers.
                Safeguard: randomness affects WHICH attacker is visited,
                not HOW they evaluate. Each agent's position × claim
                evaluation remains deterministic — contradictions are
                never relativized by path selection. *)
             let next_agent =
               List.nth_exn attackers_available
                 (Random.int (List.length attackers_available))
             in
             deliberate ~topology ~current_agent:next_agent ~arg
               ~visited:current_path)

    | Truth N ->
        (* UNKNOWN — epistemic gap: route to agents with standing on this domain.
           No defeaters added (the agent simply lacks knowledge).

           Dialectical justification: ignorance requires consulting epistemic
           authority. An N evaluation routes to arbiters, not arbitrary neighbors.
        *)
        let arbiters = Topo.get_arbiters topology current_agent arg in
        let unvisited =
          List.filter arbiters ~f:(fun n ->
            not (List.mem visited n ~equal:Agent_id.equal))
        in

        (match unvisited with
         | [] ->
             (* No arbiters available — remains unknown *)
             { argument         = arg;
               final_evaluation = Truth N;
               path             = List.rev current_path;
               defeaters_found  = arg.defeaters }
         | arbiters_available ->
             (* Randomize selection among qualified arbiters.
                Safeguard: randomness affects WHICH contradiction is found,
                not WHETHER it is preserved. B states always terminate
                immediately — they are never routed away from. *)
             let next_agent =
               List.nth_exn arbiters_available
                 (Random.int (List.length arbiters_available))
             in
             deliberate ~topology ~current_agent:next_agent ~arg
               ~visited:current_path)

  (** Execute DDG from root agent.

      Returns a dialogue_trace, NOT (chain, reward, equilibrium).
      Comparison with DIG/DEC results via scalar metrics is epistemically invalid.
  *)
  let execute ~topology ~root_agent =
    let initial_arg = Argument.root_argument () in
    deliberate
      ~topology
      ~current_agent:root_agent
      ~arg:initial_arg
      ~visited:[]

  (** Execute DDG with a caller-supplied argument.

      Use when the argument's claim content matters for evaluation
      (e.g., Páramo-specific claims that trigger position-based frameworks).
      The standard [execute] always uses [Argument.root_argument ()].
  *)
  let execute_with_arg ~topology ~root_agent ~arg =
    deliberate ~topology ~current_agent:root_agent ~arg ~visited:[]

  (** Execute DDG for a specific delegation request.

      Creates an argument representing the request and deliberates.
      Used when the delegator and potential delegatee are known.
  *)
  let execute_for_request ~topology ~delegator ~delegatee =
    let arg = Argument.of_delegation_request ~delegator ~delegatee in
    deliberate
      ~topology
      ~current_agent:delegator
      ~arg
      ~visited:[]

end
