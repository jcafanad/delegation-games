(** Simulation harness - experimental infrastructure.
    
    Replicates experimental setup from paper:
    - 156 agents (4-level tree with branching factor 5)
    - 1000 trials per run
    - 100 runs for statistical significance
    - Resource budget K ∈ [500, 800]
    - Game value V ∈ [800, 1000]
    
    Topologies:
    - Directed Trees: fixed hierarchy (root + 4 levels × 5 branches = 156 agents)
    - Random Networks: ad-hoc graphs with edge probability p
    
    Metrics:
    - PSD: Probability of Successful Delegation
    - E/R: Expenditure-Reward ratio
    - Regret: cumulative suboptimality vs oracle
*)

open Core
open Core_types
open Agent
open Protocol_dig

(** Simulation parameters *)
module Sim_params = struct
  type topology_spec =
    | Directed_tree of { levels: int; branching: int }
    | Random_network of { size: int; edge_prob: float }
  [@@deriving sexp]
  
  type t = {
    topology: topology_spec;
    num_trials: int;
    num_runs: int;
    budget_range: float * float;  (* (min, max) *)
    value_range: float * float;
    protocol_params: string Map.M(String).t;
  }
  [@@deriving sexp]
  
  (** Default parameters matching paper *)
  let paper_default _protocol_name = {
    topology = Directed_tree { levels = 4; branching = 5 };
    num_trials = 1000;
    num_runs = 100;
    budget_range = (500., 800.);
    value_range = (800., 1000.);
    protocol_params = Map.of_alist_exn (module String) [
      ("epsilon", "0.01");
      ("delta", "0.1");
      ("max_coalition_length", "3");
      ("adaptive_coalitions", "false");
    ];
  }
  
  (** Sample budget uniformly from range *)
  let sample_budget t =
    let (min_b, max_b) = t.budget_range in
    min_b +. Random.float (max_b -. min_b)
  
  (** Sample game value uniformly from range *)
  let sample_value t =
    let (min_v, max_v) = t.value_range in
    min_v +. Random.float (max_v -. min_v)
end

(** Topology generation *)
module Topology_gen = struct
  (** Generate directed tree topology.
      Returns: list of (agent_id, depth, neighbors)
  *)
  let directed_tree ~levels ~branching =
    let agent_specs = ref [] in
    let next_id = ref 0 in
    
    let rec build_level current_level parent_id =
      if current_level > levels then begin
        (* Leaf node: record with empty children list *)
        agent_specs := (parent_id, current_level - 1, []) :: !agent_specs;
        []
      end else begin
        (* Create children for this parent *)
        let children =
          List.init branching ~f:(fun _ ->
            let child_id = !next_id in
            next_id := !next_id + 1;
            child_id)
        in

        (* Record parent's neighbors as children *)
        agent_specs := (parent_id, current_level - 1, children) :: !agent_specs;

        (* Recursively build next level *)
        List.concat_map children ~f:(fun child_id ->
          build_level (current_level + 1) child_id)
      end
    in

    (* Start with root — build_level records it with its children *)
    let root_id = !next_id in
    next_id := !next_id + 1;
    ignore (build_level 1 root_id);
    
    (* Extract neighbors for each agent *)
    let neighbors_map = 
      List.fold !agent_specs 
        ~init:(Map.empty (module Agent_id))
        ~f:(fun acc (id, _, children) ->
          Map.set acc 
            ~key:(Agent_id.of_int id)
            ~data:(List.map children ~f:Agent_id.of_int))
    in
    
    (* Return (id, depth, neighbors) tuples *)
    List.map !agent_specs ~f:(fun (id, depth, _) ->
      let aid = Agent_id.of_int id in
      let neighbors = Map.find neighbors_map aid |> Option.value ~default:[] in
      (aid, depth, neighbors))
  
  (** Generate random network topology.
      Each edge (i,j) exists with probability p.
  *)
  let random_network ~size ~edge_prob =
    let agents = List.init size ~f:Agent_id.of_int in
    
    List.map agents ~f:(fun agent_id ->
      let potential_neighbors = 
        List.filter agents ~f:(fun id -> 
          not (Agent_id.equal id agent_id))
      in
      
      let neighbors = 
        List.filter potential_neighbors ~f:(fun _ ->
          Float.(Random.float 1.0 < edge_prob))
      in
      
      (* Depth will be computed via BFS later *)
      (agent_id, 0, neighbors))
end

(** Metrics collection *)
module Metrics = struct
  type trial_result = {
    chain_length: int;
    reward: Value.reward;
    budget_consumed: Resource.consumption;
    successful: bool;
    equilibrium: Equilibrium.t;
  }
  [@@deriving sexp]
  
  type run_stats = {
    trials: trial_result list;
    
    (* Aggregate metrics *)
    psd: float;  (* Probability of Successful Delegation *)
    mean_reward: float;
    total_expenditure: float;
    expenditure_reward_ratio: float;
    regret: float;
  }
  [@@deriving sexp]
  
  (** Compute PSD from trial results *)
  let compute_psd trials =
    let successes = 
      List.count trials ~f:(fun t -> t.successful)
    in
    Float.of_int successes /. Float.of_int (List.length trials)
  
  (** Compute mean reward *)
  let compute_mean_reward trials =
    let total = 
      List.sum (module Float) trials ~f:(fun t -> t.reward)
    in
    total /. Float.of_int (List.length trials)
  
  (** Compute total expenditure *)
  let compute_total_expenditure trials =
    List.sum (module Float) trials ~f:(fun t -> t.budget_consumed)
  
  (** Compute cumulative regret.
      Regret = Σ(optimal_reward - actual_reward)
      
      For oracle, assume optimal is always achieving game_value V.
  *)
  let compute_regret trials ~game_value =
    List.sum (module Float) trials ~f:(fun t ->
      game_value -. t.reward)
  
  (** Aggregate trial results into run statistics *)
  let aggregate trials ~game_value =
    let psd = compute_psd trials in
    let mean_reward = compute_mean_reward trials in
    let total_expenditure = compute_total_expenditure trials in
    let expenditure_reward_ratio = 
      if Float.(mean_reward > 0.) then
        total_expenditure /. (mean_reward *. Float.of_int (List.length trials))
      else
        Float.infinity
    in
    let regret = compute_regret trials ~game_value in
    
    {
      trials;
      psd;
      mean_reward;
      total_expenditure;
      expenditure_reward_ratio;
      regret;
    }
end

(** Main simulation engine *)
module Simulation = struct
  type result = {
    params: Sim_params.t;
    protocol: string;
    runs: Metrics.run_stats list;
    
    (* Cross-run statistics *)
    mean_psd: float;
    std_psd: float;
    mean_reward: float;
    std_reward: float;
    mean_regret: float;
    std_regret: float;
  }
  [@@deriving sexp]
  
  (** Create agent registry from topology spec *)
  let create_registry ~topology_spec ~game_value =
    let (topology, agent_specs) = 
      match topology_spec with
      | Sim_params.Directed_tree { levels; branching } ->
          (Topology.Tree { branching_factor = branching; max_depth = levels },
           Topology_gen.directed_tree ~levels ~branching)
      | Sim_params.Random_network { size; edge_prob } ->
          (Topology.Random_network { edge_probability = edge_prob },
           Topology_gen.random_network ~size ~edge_prob)
    in
    
    let registry = Agent_registry.create ~topology ~game_value in
    
    (* Create and add agents *)
    List.iter agent_specs ~f:(fun (id, depth, neighbors) ->
      let agent = Agent.create ~id ~depth ~neighbors in
      Agent_registry.add registry agent);
    
    (* Allocate values *)
    Agent_registry.allocate_values registry;
    
    registry
  
  (** Run single trial *)
  let run_trial (type a) (module P : PROTOCOL with type t = a) (protocol : a) ~budget ~initial_budget =
    let (chain, reward, equilibrium) = P.execute protocol ~budget in
    
    let successful = 
      match equilibrium with
      | Equilibrium.Resolved _ -> Float.(reward > 0.)
      | Equilibrium.Oscillating _ -> false
      | Equilibrium.Undecided -> false
    in
    
    {
      Metrics.chain_length = List.length chain;
      reward;
      budget_consumed = initial_budget -. budget;
      successful;
      equilibrium;
    }
  
  (** Run multiple trials for one run *)
  let run_trials (type a) (module P : PROTOCOL with type t = a) (protocol : a) ~params ~game_value =
    List.init params.Sim_params.num_trials ~f:(fun _ ->
      let budget = Sim_params.sample_budget params in
      run_trial (module P) protocol ~budget ~initial_budget:budget)
    |> Metrics.aggregate ~game_value
  
  (** Run full simulation (multiple runs of multiple trials) *)
  let run ~(params : Sim_params.t) ~protocol_module ~protocol_name =
    let (module P : PROTOCOL) = protocol_module in
    printf "Running %s simulation...\n%!" protocol_name;
    printf "Topology: %s\n%!" (Sexp.to_string (Sim_params.sexp_of_topology_spec params.topology));
    printf "Trials per run: %d, Runs: %d\n%!" params.num_trials params.num_runs;

    let runs =
      List.init params.num_runs ~f:(fun run_num ->
        if run_num % 10 = 0 then
          printf "  Run %d/%d\n%!" run_num params.num_runs;

        (* Create fresh registry and protocol instance for each run *)
        let game_value = Sim_params.sample_value params in
        let registry = create_registry ~topology_spec:params.topology ~game_value in
        let protocol = P.create ~registry ~params:params.protocol_params in

        run_trials (module P) protocol ~params ~game_value)
    in
    
    (* Compute cross-run statistics *)
    let psds = List.map runs ~f:(fun r -> r.Metrics.psd) in
    let rewards = List.map runs ~f:(fun r -> r.Metrics.mean_reward) in
    let regrets = List.map runs ~f:(fun r -> r.Metrics.regret) in
    
    let mean list = 
      List.sum (module Float) list ~f:Fn.id /. Float.of_int (List.length list)
    in
    
    let std list =
      let mu = mean list in
      let variance = 
        List.sum (module Float) list ~f:(fun x -> (x -. mu) ** 2.)
        /. Float.of_int (List.length list)
      in
      Float.sqrt variance
    in
    
    {
      params;
      protocol = protocol_name;
      runs;
      mean_psd = mean psds;
      std_psd = std psds;
      mean_reward = mean rewards;
      std_reward = std rewards;
      mean_regret = mean regrets;
      std_regret = std regrets;
    }
  
  (** Print summary results *)
  let print_summary result =
    printf "\n=== %s Results ===\n" result.protocol;
    printf "PSD: %.3f ± %.3f\n" result.mean_psd result.std_psd;
    printf "Reward: %.2f ± %.2f\n" result.mean_reward result.std_reward;
    printf "Regret: %.2f ± %.2f\n" result.mean_regret result.std_regret;
    printf "\n"
end
