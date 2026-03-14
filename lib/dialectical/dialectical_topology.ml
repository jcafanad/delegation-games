(** Dialectical topology: network relations encode argumentation structure.

    Replaces the semantically empty [get_neighbors] of v4 with three
    dialectically meaningful routing relations:

    - [get_attackers]: agents who can defeat this argument (for F-state routing)
    - [get_defenders]: agents who can support this argument (for robustness)
    - [get_arbiters]:  agents with epistemic standing to adjudicate (for N-state)

    Theoretical grounding:
    In Dung's abstract argumentation, routing is determined by attack/defense
    relations, not spatial proximity. This module encodes those relations into
    the network topology so that delegation decisions carry dialectical meaning.

    In the Páramo context:
    - Attackers: Paramuno communities challenging "ecosystem services" framing
    - Defenders: aligned communities supporting territorial autonomy claims
    - Arbiters:  scientists with standing on technical ecological claims
*)

open Core
open Delegation_games
open Core_types
open Agent

(** Dialectical role assigned to each agent.

    Determines which arguments each agent attacks, defends, or arbitrates,
    based on claim-pattern matching.

    Example Páramo assignments:
    - Paramuno agent: Attacker_of ["ecosystem services"; "conservation"]
    - Aligned community: Defender_of ["territorial"]
    - Scientist: Arbiter_of ["water"; "biodiversity"; "ecosystem"]
*)
type dialectical_role =
  | Attacker_of of string list
      (** Agent attacks arguments whose claim contains one of these substrings *)
  | Defender_of of string list
      (** Agent defends arguments whose claim contains one of these substrings *)
  | Arbiter_of of string list
      (** Agent arbitrates arguments in these domains *)
  | Neutral
      (** Agent has no dialectical stance — will not be selected by role-based routing *)
[@@deriving sexp]

(** Module type for dialectical topologies.

    Implementations must map each routing decision to a list of agent IDs.
    The DDG functor uses this to route based on Belnap evaluation:
    - Truth F → get_attackers  (burden of proof)
    - Truth N → get_arbiters   (epistemic standing)
    - Truth B → no routing     (contradiction preserved)
    - Truth T → no routing     (accepted)
*)
module type S = sig
  type t

  (** Agents with knowledge to attack (defeat) this argument.
      Called when current agent evaluates to F. *)
  val get_attackers : t -> Agent_id.t -> Argument.t -> Agent_id.t list

  (** Agents with knowledge to defend (support) this argument.
      Called when seeking robustness confirmation after T. *)
  val get_defenders : t -> Agent_id.t -> Argument.t -> Agent_id.t list

  (** Agents with epistemic standing to adjudicate.
      Called when current agent evaluates to N. *)
  val get_arbiters : t -> Agent_id.t -> Argument.t -> Agent_id.t list
end

(** Helper: get neighbor IDs for an agent, given their ID. *)
let neighbors_of_id registry agent_id =
  match Agent_registry.get registry agent_id with
  | None       -> []
  | Some agent -> Agent_registry.get_neighbors registry agent

(** Helper: check if an argument's claim matches any of the given patterns. *)
let matches_pattern (arg : Argument.t) patterns =
  List.exists patterns ~f:(fun p ->
    String.is_substring arg.claim ~substring:p)

(** Role-based dialectical topology.

    Assigns a [dialectical_role] to each agent. Routing queries filter
    direct neighbors by their assigned role and claim-pattern matching.

    Usage:
    {[
      let topo = Simple_dialectical_topology.create_neutral ~base_topology:registry in
      Simple_dialectical_topology.assign_role topo paramuno_id
        (Attacker_of ["ecosystem services"; "conservation"]);
      Simple_dialectical_topology.assign_role topo scientist_id
        (Arbiter_of ["water"; "biodiversity"]);
    ]}
*)
module Simple_dialectical_topology = struct
  type t = {
    base_topology : Agent_registry.t;
    roles         : (Agent_id.t, dialectical_role) Hashtbl.t;
  }

  let create ~base_topology ~roles = { base_topology; roles }

  (** Create topology where all agents start as [Neutral]. *)
  let create_neutral ~base_topology =
    { base_topology; roles = Hashtbl.create (module Agent_id) }

  let assign_role t agent_id role =
    Hashtbl.set t.roles ~key:agent_id ~data:role

  let get_attackers t agent_id arg =
    let neighbors = neighbors_of_id t.base_topology agent_id in
    List.filter neighbors ~f:(fun n ->
      match Hashtbl.find t.roles n with
      | Some (Attacker_of patterns) -> matches_pattern arg patterns
      | _ -> false)

  let get_defenders t agent_id arg =
    let neighbors = neighbors_of_id t.base_topology agent_id in
    List.filter neighbors ~f:(fun n ->
      match Hashtbl.find t.roles n with
      | Some (Defender_of patterns) -> matches_pattern arg patterns
      | _ -> false)

  let get_arbiters t agent_id arg =
    let neighbors = neighbors_of_id t.base_topology agent_id in
    List.filter neighbors ~f:(fun n ->
      match Hashtbl.find t.roles n with
      | Some (Arbiter_of domains) -> matches_pattern arg domains
      | _ -> false)
end

(** Fallback topology: all three routing functions return all neighbors.

    Semantically equivalent to v4's [get_neighbors] — no dialectical meaning,
    but preserves the existing behavior for comparison and testing.

    Use when dialectical role structure is unknown or when reproducing v4.
*)
module Fallback_topology = struct
  type t = Agent_registry.t

  let get_attackers t agent_id _arg = neighbors_of_id t agent_id
  let get_defenders t agent_id _arg = neighbors_of_id t agent_id
  let get_arbiters  t agent_id _arg = neighbors_of_id t agent_id
end
