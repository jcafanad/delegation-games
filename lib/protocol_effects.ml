(** Direct implementation of delegation effects.

    This is the "simple" version that will be replaced with effect handlers
    in Phase 2. Kept separate to make the transition clear.
*)

open Core_types
open Agent

type decision = Agent_id.t option
type outcome = Value.reward

module type DELEGATION_EFFECTS = sig
  val decide_delegation :
    agent:Agent.t ->
    neighbors:Agent.t list ->
    registry:Agent_registry.t ->
    decision

  val sample_outcome :
    agent:Agent.t ->
    game_value:Value.game_value ->
    outcome

  val update_belief :
    agent:Agent.t ->
    outcome:outcome ->
    unit
end

module Direct_effects = struct
  (** Return the first available neighbor, or None.
      Real delegation logic lives in the protocol-specific modules (DIG/DEC/DDG).
      This provides a minimal fallback for testing and scaffolding.
  *)
  let decide_delegation ~agent:_ ~neighbors ~registry:_ =
    match neighbors with
    | [] -> None
    | hd :: _ -> Some (Agent.id hd)

  let sample_outcome ~agent ~game_value =
    let allocation = Agent.allocated_value agent in
    Value.sample_outcome ~allocation ~game_value

  let update_belief ~agent ~outcome =
    if outcome > 0. then
      Agent.increment_successes agent
    else
      Agent.increment_failures agent
end

(** Prepare for effect-based implementation (Phase 2).

    The module below shows what the OCaml 5 effect-based version will look like.
    Commented out because it requires OCaml 5 effects.

    module Effect_based : Protocol_effects.DELEGATION_EFFECTS = struct
      type _ Effect.t +=
        | Decide : Agent.t * Agent.t list * Agent_registry.t -> decision Effect.t
        | Sample : Agent.t * Value.game_value -> outcome Effect.t
        | Update : Agent.t * outcome -> unit Effect.t

      let decide_delegation ~agent ~neighbors ~registry =
        Effect.perform (Decide (agent, neighbors, registry))

      let sample_outcome ~agent ~game_value =
        Effect.perform (Sample (agent, game_value))

      let update_belief ~agent ~outcome =
        Effect.perform (Update (agent, outcome))
    end
*)
