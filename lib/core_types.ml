(** Core types for delegation games.
    
    This module defines the fundamental structures for modeling delegation as:
    - Hierarchical extraction (DIG): value flows upward through delegation chains
    - Coalitional resistance (DEC): agents cooperate to sustain under constraints
    - Dialectical refusal (DDG): simultaneous acceptance/rejection of delegation
    
    Theoretical foundations:
    - Delegation chains model hierarchical superstructures (State, capital)
    - Resource constraints model material conditions of resistance
    - Oscillations model contradictions inherent to extractive relations
*)

open Core

(** Agent identifiers - indices in delegation hierarchy *)
module Agent_id : sig
  type t = private int [@@deriving sexp, compare, equal, hash]
  
  val of_int : int -> t
  val to_int : t -> int
  val root : t  (* agent initiating delegation cascade *)
  
  include Comparable.S with type t := t
  include Hashable.S with type t := t
end = struct
  module T = struct
    type t = int [@@deriving sexp, compare, equal, hash]
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
  
  let of_int i = if i < 0 then failwith "Agent_id must be non-negative" else i
  let to_int = Fn.id
  let root = 0
end

(** Delegation actions - execute vs delegate with theoretical interpretation.
    
    Execute: agent performs task (accepts domination/completes extraction)
    Delegate: agent passes task onward (refuses/redirects extraction)
    Reject: agent returns task (refusal without alternative - forced self-execution)
    
    In DDG mode, these become dialetheic: agent can Execute AND Delegate simultaneously.
*)
module Action = struct
  type t =
    | Execute   (* e_i: complete task, receive rewards, end delegation chain *)
    | Delegate of Agent_id.t  (* d_{i,j}: pass task to agent j *)
    | Reject    (* d_i: return task to delegator, forcing their execution *)
  [@@deriving sexp, variants, equal]
end

(** Value and reward structures encoding hierarchical extraction.
    
    The allocation rule v_i/(i+1) = V/T_n where T_n = n(n+1)/2 reflects:
    - Agents farther from root get higher potential value (positioned to "develop")
    - But rewards flow inversely: r_{i,j}/i = o_k/H_k where H_k = sum(1/i)
    - This models surplus extraction - value potential vs realized accumulation
    
    Flexibility: formula can adapt to non-tree topologies by computing depth
    via shortest path from root rather than level in tree.
*)
module Value = struct
  type t = float [@@deriving sexp]
  
  (** Total value of game - maximum extractable surplus *)
  type game_value = t
  
  (** Allocated potential value per agent based on depth *)
  type allocation = t
  
  (** Realized reward from delegation chain - flows inversely to root *)
  type reward = t [@@deriving sexp]
  
  (** Compute triangular number T_n = n(n+1)/2 *)
  let triangular n = Float.of_int n *. Float.of_int (n + 1) /. 2.
  
  (** Compute harmonic number H_n = sum_{i=1}^n 1/i *)
  let harmonic n =
    List.init n ~f:(fun i -> 1. /. Float.of_int (i + 1))
    |> List.fold ~init:0. ~f:(+.)
  
  (** Allocate value to agent at depth d in hierarchy of size n.
      v_d = (d+1) * V / T_n
      
      Reflects: deeper agents have more potential to generate value
      (positioned in extractive hierarchy to "sense" or "develop")
  *)
  let allocate ~game_value ~depth ~hierarchy_size =
    let d = Float.of_int depth in
    let t_n = triangular hierarchy_size in
    (d +. 1.) *. game_value /. t_n
  
  (** Sample outcome from uniform distribution U(v_i, V).
      Represents stochastic realization of value potential.
  *)
  let sample_outcome ~allocation ~game_value =
    allocation +. Random.float (game_value -. allocation)

  (** Distribute outcome as rewards inversely through coalition.
      r_i = outcome / (i * H_k) where k = |coalition|

      Position is 1-indexed with 1 = first delegator (closest to root).
      Reflects: rewards flow upward toward root (position 1 captures most),
      and sum of all rewards equals outcome: Σ (1/i) / H_k = H_k / H_k = 1.
  *)
  let distribute_reward ~outcome ~position ~coalition_size =
    let pos = Float.of_int position in
    let h_k = harmonic coalition_size in
    outcome /. (pos *. h_k)

  (** Factor by which expected outcome increases when delegating one level deeper.
      Derived from allocation formula v_d = (d+1)*V/T_n:
        v_{d+1} / v_d = (d+2) / (d+1)
      Delegation is rational when this gain outweighs the cost of splitting
      the outcome with one more agent (longer harmonic series denominator).
  *)
  let depth_delegation_factor ~current_depth =
    Float.of_int (current_depth + 2) /. Float.of_int (current_depth + 1)

  (** Compute quitting game reward comparison for DIG strategy formula.

      Returns (r_{i,0}, r_{i,1}) where:
      - r_{i,0}: agent i's reward if neighbor executes   (chain [i,j], pos 1 of 2)
      - r_{i,1}: agent i's reward if neighbor delegates  (chain [i,j,k], pos 1 of 3,
                 outcome scaled by depth gain from allocation formula)

      Used in: x_{i,j} = (r_{i,1} - r_{i,0}) / (r_{i,j} - r_j)
  *)
  let quitting_game_rewards ~neighbor_outcome ~neighbor_depth =
    let r_i_0 =
      distribute_reward ~outcome:neighbor_outcome ~position:1 ~coalition_size:2
    in
    let depth_gain = depth_delegation_factor ~current_depth:neighbor_depth in
    let r_i_1 =
      distribute_reward
        ~outcome:(neighbor_outcome *. depth_gain)
        ~position:1
        ~coalition_size:3
    in
    (r_i_0, r_i_1)
end

(** Resource constraints - material limits on delegation capacity.
    
    K represents productive resource enabling delegation (energy, time, attention).
    Each delegation consumes resources proportional to success rate:
    - consumption = 1 / (α + β) where α = successes, β = failures
    
    This models learning efficiency: better-known delegatees consume less resources.
    Critical for DEC: cooperation must sustain longer under same constraints.
*)
module Resource = struct
  type budget = float [@@deriving sexp]
  type consumption = float [@@deriving sexp]
  
  (** Compute consumption rate based on delegation history.
      Rate = 1 / (successes + failures)
      
      Interpretation: established relationships consume fewer resources.
      This encodes trust as resource efficiency, not abstract belief.
  *)
  let consumption_rate ~successes ~failures =
    1. /. Float.of_int (successes + failures)
  
  (** Check if budget permits delegation *)
  let can_delegate ~budget ~consumption = Float.(budget >= consumption)
  
  (** Update budget after delegation *)
  let consume ~budget ~consumption = Float.max 0. (budget -. consumption)
end

(** Delegation chains - sequences of agents forming hierarchical/cooperative structures.
    
    Chain represents both:
    - Path of extraction (hierarchical reading: root → delegatees)
    - Coalition formation (cooperative reading: shared objective)
    
    The ambiguity is intentional - DIG reads chains hierarchically,
    DEC reads them coalitionally, DDG reads them dialectically.
*)
module Delegation_chain = struct
  type t = Agent_id.t list [@@deriving sexp]
  
  let root = function
    | [] -> None
    | hd :: _ -> Some hd
  
  let terminal = function
    | [] -> None
    | lst -> Some (List.last_exn lst)
  
  let length = List.length
  
  (** Compute depth of agent in chain (0 = root) *)
  let depth chain agent =
    List.findi chain ~f:(fun _ id -> Agent_id.equal id agent)
    |> Option.map ~f:fst
  
  (** Check if chain forms valid delegation (no cycles, within length limit) *)
  let is_valid ~max_length chain =
    length chain <= max_length &&
    List.contains_dup chain ~compare:Agent_id.compare |> not
  
  (** Convert chain to coalition for Shapley/Myerson computation *)
  let to_coalition = List.sort ~compare:Agent_id.compare
end

(** Equilibrium states - outcomes of strategic interaction.
    
    ε-equilibrium: approximate Nash where strategies are within ε of optimal
    Oscillating: cyclic pattern of delegation/rejection (unresolved contradiction)
    
    DDG mode preserves Oscillating as legitimate state rather than failure.
*)
module Equilibrium = struct
  type resolved = {
    strategy: float; (* probability of delegating *)
    reward: Value.reward;
    epsilon: float; (* distance from true Nash *)
  } [@@deriving sexp]
  
  type oscillating = {
    cycle: (Agent_id.t * Action.t) list;
    period: int;
    rewards: Value.reward list; (* reward stream over cycle *)
  } [@@deriving sexp]
  
  type t =
    | Resolved of resolved
    | Oscillating of oscillating
    | Undecided (* DDG: simultaneously resolved and oscillating *)
  [@@deriving sexp, variants]
  
  (** Check if strategy profile forms ε-equilibrium:
      v_i(x) >= v_i(x_{-i}, y_i) - ε for all alternative strategies y_i
  *)
  let is_epsilon_equilibrium ~epsilon ~current_reward ~alternative_reward =
    Float.(current_reward >= alternative_reward -. epsilon)
end

(** Topology - graph structure enabling/constraining delegation.
    
    Tree: fixed hierarchy (State bureaucracy, corporate org chart)
    Random: emergent network (discovered through delegation attempts)
    General: arbitrary graph (territorial disputes, overlapping jurisdictions)
*)
module Topology = struct
  type t =
    | Tree of { branching_factor: int; max_depth: int }
    | Random_network of { edge_probability: float }
    | General_graph (* defined by explicit adjacency *)
  [@@deriving sexp]
  
  (** Neighbor relation - who can be delegated to *)
  type neighbors = Agent_id.t list [@@deriving sexp]
end
