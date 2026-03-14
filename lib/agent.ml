(** Agent module - maintains state and computes delegation strategies.
    
    Agents are:
    - Learners: update α (successes) and β (failures) from delegation outcomes
    - Strategists: compute probability of delegating based on accumulated knowledge
    - Positioned: have depth in hierarchy, neighbors in topology
    
    The same agent type is used across protocols (DIG/DEC/DDG) but interprets
    state differently:
    - DIG: strategies are quitting game probabilities
    - DEC: strategies guide coalition formation  
    - DDG: strategies can be contradictory (delegate AND execute)
*)

open Core
open Core_types

module type AGENT = sig
  type t
  
  (** Creation and identification *)
  val create : id:Agent_id.t -> depth:int -> neighbors:Agent_id.t list -> t
  val id : t -> Agent_id.t
  val depth : t -> int
  val neighbors : t -> Agent_id.t list
  
  (** Learning state - mutable counters *)
  val successes : t -> int
  val failures : t -> int
  val increment_successes : t -> unit
  val increment_failures : t -> unit
  
  (** Strategy computation *)
  val strategy : t -> float  (* probability of delegating *)
  val update_strategy : t -> reward_execute:Value.reward -> reward_delegate:Value.reward -> unit
  
  (** Allocation and rewards *)
  val allocated_value : t -> Value.allocation
  val set_allocated_value : t -> Value.allocation -> unit
  val last_reward : t -> Value.reward option
  val set_last_reward : t -> Value.reward -> unit
  
  (** Resource tracking *)
  val consumption_rate : t -> Resource.consumption
end

module Agent : AGENT = struct
  type t = {
    id: Agent_id.t;
    depth: int;
    neighbors: Agent_id.t list;
    
    (* Mutable learning state *)
    mutable successes: int;
    mutable failures: int;
    mutable strategy: float;
    
    (* Mutable value tracking *)
    mutable allocated_value: Value.allocation;
    mutable last_reward: Value.reward option;
  }
  
  let create ~id ~depth ~neighbors = {
    id;
    depth;
    neighbors;
    successes = 0;
    failures = 0;
    strategy = 0.5;  (* uninformed prior *)
    allocated_value = 0.;
    last_reward = None;
  }
  
  let id t = t.id
  let depth t = t.depth
  let neighbors t = t.neighbors
  let successes t = t.successes
  let failures t = t.failures
  
  let increment_successes t = t.successes <- t.successes + 1
  let increment_failures t = t.failures <- t.failures + 1
  
  let strategy t = t.strategy
  
  (** Update strategy based on quitting game logic.
      x_{i,j} = (r_{i,1} - r_{i,0}) / (r_{i,j} - r_j)
      
      Interpretation:
      - Numerator: gain from delegatee accepting vs rejecting
      - Denominator: relative reward between delegator and delegatee
      - Result: probability that delegation is profitable
  *)
  let update_strategy t ~reward_execute ~reward_delegate =
    let numerator = reward_delegate -. reward_execute in
    let denominator = reward_delegate in
    if Float.(abs denominator < 1e-10) then
      t.strategy <- 0.
    else
      t.strategy <- Float.max 0. (Float.min 1. (numerator /. denominator))
  
  let allocated_value t = t.allocated_value
  let set_allocated_value t v = t.allocated_value <- v
  
  let last_reward t = t.last_reward
  let set_last_reward t r = 
    t.last_reward <- Some r
  
  let consumption_rate t =
    Resource.consumption_rate ~successes:t.successes ~failures:t.failures
end

(** Agent registry - maintains population and topology.
    
    Provides global view for:
    - Value allocation (needs hierarchy size)
    - Coalition formation (needs graph structure)
    - Characteristic function learning (needs coalition history)
*)
module Agent_registry = struct
  type t = {
    agents: (Agent_id.t, Agent.t) Hashtbl.t;
    topology: Topology.t;
    game_value: Value.game_value;
  }
  
  let create ~topology ~game_value =
    { agents = Hashtbl.create (module Agent_id);
      topology;
      game_value }
  
  let add t agent =
    Hashtbl.set t.agents ~key:(Agent.id agent) ~data:agent
  
  let get t id = Hashtbl.find t.agents id
  
  let get_exn t id = 
    Hashtbl.find_exn t.agents id
  
  let size t = Hashtbl.length t.agents
  
  (** Allocate values to all agents based on depth in hierarchy *)
  let allocate_values t =
    let hierarchy_size = size t in
    Hashtbl.iter t.agents ~f:(fun agent ->
      let allocation = 
        Value.allocate 
          ~game_value:t.game_value 
          ~depth:(Agent.depth agent)
          ~hierarchy_size
      in
      Agent.set_allocated_value agent allocation)
  
  (** Sample outcomes for all agents *)
  let sample_outcomes t =
    Hashtbl.map t.agents ~f:(fun agent ->
      let allocation = Agent.allocated_value agent in
      Value.sample_outcome ~allocation ~game_value:t.game_value)
  
  (** Get neighbors of agent according to topology *)
  let get_neighbors _t agent =
    (* For now, use agent's stored neighbors *)
    (* TODO: compute dynamically for Random_network topology *)
    Agent.neighbors agent
  
  (** Compute depth via BFS from root for general topologies *)
  let compute_depths t =
    let depths = Hashtbl.create (module Agent_id) in
    let visited = Hash_set.create (module Agent_id) in
    let queue = Queue.create () in
    
    (* Start from root *)
    Queue.enqueue queue (Agent_id.root, 0);
    
    while not (Queue.is_empty queue) do
      let (current_id, depth) = Queue.dequeue_exn queue in
      if not (Hash_set.mem visited current_id) then begin
        Hash_set.add visited current_id;
        Hashtbl.set depths ~key:current_id ~data:depth;
        
        (* Enqueue neighbors *)
        match get t current_id with
        | None -> ()
        | Some agent ->
            List.iter (Agent.neighbors agent) ~f:(fun neighbor_id ->
              Queue.enqueue queue (neighbor_id, depth + 1))
      end
    done;
    depths
end
