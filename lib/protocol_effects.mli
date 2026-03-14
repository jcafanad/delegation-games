(** Effect signatures for delegation protocols.

    This interface defines the operations that will eventually become
    algebraic effects in Phase 2. Current implementation uses direct
    function calls, but the signature prepares for effect handler transition.

    Theoretical interpretation:
    - Delegation decision is effectful (depends on stochastic outcomes)
    - Learning updates are effectful (modify agent beliefs)
    - Outcome sampling is effectful (draws from distributions)

    Phase 2 will implement via OCaml 5 effects:
      type _ Effect.t +=
        | Decide : Agent.t * Agent.t list -> Agent_id.t option Effect.t
        | Sample : Agent.t -> float Effect.t
        | Update : Agent.t * float -> unit Effect.t
*)

open Core_types
open Agent

(** Decision outcome: which agent to delegate to (or None for execute) *)
type decision = Agent_id.t option

(** Outcome of task execution *)
type outcome = Value.reward

(** Effect interface for delegation decisions *)
module type DELEGATION_EFFECTS = sig
  (** Decide whether to delegate and to whom.

      Current: computes directly from agent strategies
      Future:  Effect.perform (Decide (agent, neighbors))
  *)
  val decide_delegation :
    agent:Agent.t ->
    neighbors:Agent.t list ->
    registry:Agent_registry.t ->
    decision

  (** Sample stochastic outcome from delegation.

      Current: samples from uniform distribution
      Future:  Effect.perform (Sample agent)
  *)
  val sample_outcome :
    agent:Agent.t ->
    game_value:Value.game_value ->
    outcome

  (** Update agent belief from observed outcome.

      Current: increment α/β counters directly
      Future:  Effect.perform (Update (agent, outcome))
  *)
  val update_belief :
    agent:Agent.t ->
    outcome:outcome ->
    unit
end

(** Direct (non-effectful) implementation of DELEGATION_EFFECTS.
    Used in Phase 1. Phase 2 will add an effect-handler based implementation.
*)
module Direct_effects : DELEGATION_EFFECTS
