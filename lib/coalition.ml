(** Characteristic function and solution concepts for coalitional games.
    
    In delegation context:
    - Coalitions are delegation chains (ordered sequences)
    - Values are summed rewards from chain execution
    - Shapley value: individual contribution independent of graph structure
    - Myerson value: contribution restricted to connected coalitions
    
    Theoretical interpretation:
    - ν(D) represents collective value of cooperation within delegation chain D
    - Shapley value: agent's marginal contribution across all possible orderings
    - Myerson value: contribution respecting topology (can't cooperate with disconnected)
    
    This encodes cooperation as ontologically prior to individual agency -
    agents are constituted by their coalitional contributions, not reducible to them.
*)

open Core
open Core_types

(** Coalition representation.
    
    Uses sorted agent IDs for canonicalization (set semantics).
    But delegation chains are ordered, so we preserve both:
    - coalition: unordered set for Shapley computation
    - chain: ordered sequence for delegation semantics
*)
module Coalition = struct
  module T = struct
    type t = Agent_id.t list [@@deriving sexp, compare, hash]
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
  
  let empty = []
  
  let singleton id = [id]
  
  let of_chain chain =
    List.sort chain ~compare:Agent_id.compare
    |> List.dedup_and_sort ~compare:Agent_id.compare
  
  let to_chain t = t  (* coalition already sorted *)
  
  let size = List.length
  
  let mem coalition agent =
    List.mem coalition agent ~equal:Agent_id.equal
  
  let remove coalition agent =
    List.filter coalition ~f:(fun id -> not (Agent_id.equal id agent))
  
  (** Generate all subsets of coalition *)
  let power_set coalition =
    let rec aux = function
      | [] -> [[]]
      | x :: xs ->
          let rest = aux xs in
          rest @ List.map rest ~f:(fun subset -> x :: subset)
    in
    aux coalition
  
  (** Check if coalition is connected in graph.
      Required for Myerson value computation.
  *)
  let is_connected coalition ~get_neighbors =
    match coalition with
    | [] | [_] -> true
    | first :: _rest ->
        let visited = Core.Hash_set.create (module Agent_id) in
        let queue = Queue.create () in
        Queue.enqueue queue first;

        while not (Queue.is_empty queue) do
          let current = Queue.dequeue_exn queue in
          if not (Core.Hash_set.mem visited current) && mem coalition current then begin
            Core.Hash_set.add visited current;
            List.iter (get_neighbors current) ~f:(fun neighbor ->
              if mem coalition neighbor then
                Queue.enqueue queue neighbor)
          end
        done;

        List.for_all coalition ~f:(fun id -> Core.Hash_set.mem visited id)
end

(** Characteristic function ν: 2^N → ℝ mapping coalitions to values.
    
    Learning mechanism:
    - Decentralized: each agent maintains local view of coalitions they've participated in
    - Convergence: over time, local views approximate global coalition structure
    - Updates: when delegation chain completes, all members update ν with realized rewards
    
    This implements the "learning of global structure through local participation"
    commitment - agents don't have god's-eye view, but cooperate toward shared understanding.
*)
module Characteristic_function = struct
  type t = {
    values: (Coalition.t, Value.reward) Hashtbl.t;
    updates: int;  (* count of total updates for averaging *)
  }
  
  let create () = {
    values = Hashtbl.create (module Coalition);
    updates = 0;
  }
  
  (** Update characteristic function with observed coalition value.
      Uses exponential moving average to incorporate new information:
      ν_new(D) = α * observed + (1-α) * ν_old(D)
      where α = 1/(update_count + 1)
  *)
  let update t coalition value =
    let alpha = 1. /. Float.of_int (t.updates + 1) in
    let new_value = 
      match Hashtbl.find t.values coalition with
      | None -> value
      | Some old_value -> alpha *. value +. (1. -. alpha) *. old_value
    in
    Hashtbl.set t.values ~key:coalition ~data:new_value;
    { t with updates = t.updates + 1 }
  
  (** Lookup coalition value, returning 0 if unknown *)
  let lookup t coalition =
    Hashtbl.find t.values coalition
    |> Option.value ~default:0.
  
  (** Compute marginal contribution of agent to coalition.
      ν(D) - ν(D \ {i})
      
      This is the core of Shapley value: how much does i contribute
      to coalition D's collective value?
  *)
  let marginal t agent coalition =
    let with_agent = lookup t coalition in
    let without_agent = lookup t (Coalition.remove coalition agent) in
    with_agent -. without_agent
end

(** Shapley value computation via marginal contributions.
    
    Sh_i(N; ν) = Σ_{D⊆N} g_D [ν(D) - ν(D\{i})]
    where g_D = (|D|-1)!(n-|D|)! / n!
    
    Interpretation:
    - Sum over all coalitions D containing i
    - Weight by number of orderings where i joins D
    - Result: average marginal contribution across all possible formations
    
    Computational note: uses divide-and-conquer backtracking for efficiency.
    Still exponential in coalition size, hence myopic horizon (max 3 agents).
*)
module Shapley = struct
  (** Compute weight g_D = (|D|-1)!(n-|D|)! / n! *)
  let weight coalition_size total_agents =
    let open Float in
    let d = of_int coalition_size in
    let n = of_int total_agents in
    let factorial k =
      List.range 1 Int.(of_float k + 1)
      |> List.fold ~init:1. ~f:(fun acc i -> acc *. of_int i)
    in
    factorial (d - 1.) *. factorial (n - d) /. factorial n
  
  (** Compute Shapley value for agent across all coalitions.
      
      Uses backtracking to enumerate subsets efficiently:
      - Start with full coalition
      - Recursively remove members
      - Compute marginal contribution at each step
  *)
  let value char_func agent all_agents =
    let total_agents = List.length all_agents in
    let rec compute coalition =
      if Coalition.mem coalition agent then
        let marginal = Characteristic_function.marginal char_func agent coalition in
        let weighted = weight (Coalition.size coalition) total_agents *. marginal in
        
        (* Recursively compute for subcoalitions *)
        let subcoalitions = 
          List.filter coalition ~f:(fun id -> not (Agent_id.equal id agent))
          |> Coalition.power_set
          |> List.filter ~f:(fun sub -> Coalition.mem sub agent)
        in
        weighted +. List.sum (module Float) subcoalitions ~f:compute
      else
        0.
    in
    compute (Coalition.of_chain all_agents)
end

(** Myerson value - Shapley value restricted to connected coalitions.
    
    My_i(N; ν) = Sh_i(N; ν_M)
    where ν_M(D) = { ν(D) if D ∈ S(N) (D is connected)
                   { Σ_{K∈K(D)} ν(K) otherwise (sum over connected components)
    
    Interpretation:
    - Cooperation requires connection (can't cooperate with disconnected)
    - Reflects topology as constraint on coalitional possibilities
    - In delegation: can only cooperate with reachable delegatees
    
    This encodes material/geographical constraints on cooperation -
    Paramunos can't form coalitions with distant communities, cooperation
    is embedded in territorial proximity.
*)
module Myerson = struct
  (** Compute connected components of coalition *)
  let connected_components coalition ~get_neighbors =
    let visited = Hash_set.create (module Agent_id) in
    let components = ref [] in
    
    List.iter coalition ~f:(fun start ->
      if not (Hash_set.mem visited start) then
        let component = ref [] in
        let queue = Queue.create () in
        Queue.enqueue queue start;
        
        while not (Queue.is_empty queue) do
          let current = Queue.dequeue_exn queue in
          if not (Hash_set.mem visited current) && Coalition.mem coalition current then begin
            Hash_set.add visited current;
            component := current :: !component;
            List.iter (get_neighbors current) ~f:(fun neighbor ->
              if Coalition.mem coalition neighbor then
                Queue.enqueue queue neighbor)
          end
        done;
        
        components := !component :: !components);
    !components
  
  (** Compute modified characteristic function ν_M *)
  let modified_char_func char_func ~get_neighbors =
    let t = Characteristic_function.create () in
    Hashtbl.iteri char_func.Characteristic_function.values ~f:(fun ~key:coalition ~data:value ->
      let modified_value =
        if Coalition.is_connected coalition ~get_neighbors then
          value
        else
          (* Sum values of connected components *)
          connected_components coalition ~get_neighbors
          |> List.sum (module Float) ~f:(fun component ->
              Characteristic_function.lookup char_func component)
      in
      ignore (Characteristic_function.update t coalition modified_value));
    t
  
  (** Compute Myerson value using modified characteristic function *)
  let value char_func agent all_agents ~get_neighbors =
    let nu_m = modified_char_func char_func ~get_neighbors in
    Shapley.value nu_m agent all_agents
end

(** Solution concept selector - chooses Shapley or Myerson based on topology.
    
    Use Shapley for:
    - Complete graphs (all agents can cooperate)
    - Abstract analysis ignoring topology
    
    Use Myerson for:
    - Tree/network topologies (connectivity matters)
    - Realistic scenarios with geographical/social distance
*)
module Solution_concept = struct
  type t = 
    | Shapley
    | Myerson
  [@@deriving sexp]
  
  let of_topology = function
    | Topology.Tree _ -> Myerson
    | Topology.Random_network _ -> Myerson
    | Topology.General_graph -> Myerson
  
  let compute t char_func agent all_agents ~get_neighbors =
    match t with
    | Shapley -> Shapley.value char_func agent all_agents
    | Myerson -> Myerson.value char_func agent all_agents ~get_neighbors
end
