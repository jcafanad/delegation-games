(** Delegation protocols - DIG (hierarchical) and DEC (coalitional).
    
    Common interface:
    - decide: determine delegation action based on current state
    - learn: update internal state from delegation outcome
    - execute: run full delegation cascade from root
    
    DIG (Delegation as Iterative Game):
    - Models hierarchical extraction via quitting games
    - Agents compute mixed strategies (probability of delegating)
    - Selection via ε-equilibrium (approximate Nash)
    - Value flows upward through delegation chain
    
    DEC (Delegation as Coalitional):
    - Models cooperative resistance via Shapley/Myerson
    - Agents form coalitions to maximize collective value
    - Selection via marginal contributions
    - More resource-efficient but potentially lower rewards
*)

open Core
open Core_types
open Agent

(** Common protocol signature *)
module type PROTOCOL = sig
  type t
  
  (** Initialize protocol with registry and parameters *)
  val create : registry:Agent_registry.t -> params:string Map.M(String).t -> t
  
  (** Decide delegation action for given agent.
      Returns: (action, updated_protocol)
      
      Side effects: may update agent state (α, β counters, strategies)
  *)
  val decide : t -> agent:Agent.t -> budget:Resource.budget -> 
    (Action.t * t)
  
  (** Learn from delegation outcome.
      Updates characteristic function (DEC) or strategies (DIG).
  *)
  val learn : t -> chain:Delegation_chain.t -> outcome:Value.reward -> t
  
  (** Execute full delegation cascade starting from root.
      Returns: (delegation_chain, total_reward, equilibrium_state)
  *)
  val execute : t -> budget:Resource.budget -> 
    (Delegation_chain.t * Value.reward * Equilibrium.t)
  
  (** Get protocol name for logging *)
  val name : string
end

(** DIG Protocol - Quitting Game Implementation.
    
    Algorithm 11 from thesis:
    
    function DIG(P_i, r_i):
      S_i ← ∅, x_i ← ∅
      for a_j ∈ ad_i:
        x_{i,j} = (r_{i,1} - r_{i,0}) / (r_{i,j} - r_j)
        x_i ← x_i ∪ {x_{i,j}}
      while ∃j[(x_{i,j} ≠ 0 ∧ ad_j ≠ ∅)]:
        m ← argmax_{j∈ad_i}(r_{i,j})
        if (1-δ < x_{i,m}):
          if a_m ∈ S_i:
            Update r_{i,m}, x_{i,m}
          else:
            S_i ← S_i ∪ {a_m}
            return LEARN(P_m, r_m; x_i)
        else:
          a_i executes task
      return (S_i, x_i)
*)
module DIG : PROTOCOL = struct
  type t = {
    registry: Agent_registry.t;
    epsilon: float;  (* ε-equilibrium tolerance *)
    delta: float;    (* state of nature threshold *)
  }
  
  let name = "DIG"
  
  let create ~registry ~params =
    let epsilon = 
      Map.find params "epsilon"
      |> Option.map ~f:Float.of_string
      |> Option.value ~default:0.01
    in
    let delta =
      Map.find params "delta"
      |> Option.map ~f:Float.of_string
      |> Option.value ~default:0.1
    in
    { registry; epsilon; delta }
  
  (** Compute strategies for all neighbors.
      x_{i,j} = (r_{i,1} - r_{i,0}) / (r_{i,j} - r_j)
  *)
  let compute_strategies t ~agent =
    let agent_id = Agent.id agent in
    let neighbors = Agent.neighbors agent in
    
    (* Sample outcomes for agent and all neighbors *)
    let outcomes = Agent_registry.sample_outcomes t.registry in
    let _agent_outcome = Hashtbl.find_exn outcomes agent_id in
    
    List.map neighbors ~f:(fun neighbor_id ->
      match Agent_registry.get t.registry neighbor_id with
      | None -> None
      | Some neighbor ->
          let neighbor_outcome = Hashtbl.find_exn outcomes neighbor_id in
          
          (* r_{i,0}, r_{i,1}: quitting game rewards from Value module.
             r_{i,0} = i's share when neighbor executes (chain of 2)
             r_{i,1} = i's share when neighbor delegates further (chain of 3,
                       outcome scaled by depth gain from allocation formula)
          *)
          let (reward_if_neighbor_executes, reward_if_neighbor_delegates) =
            Value.quitting_game_rewards
              ~neighbor_outcome
              ~neighbor_depth:(Agent.depth neighbor)
          in
          let expected_reward = (reward_if_neighbor_delegates +. reward_if_neighbor_executes) /. 2. in
          
          (* Strategy formula from quitting game *)
          let numerator = reward_if_neighbor_delegates -. reward_if_neighbor_executes in
          let denominator = expected_reward -. neighbor_outcome in
          
          let strategy = 
            if Float.(abs denominator < 1e-10) then 0.
            else Float.max 0. (Float.min 1. (numerator /. denominator))
          in
          
          Some (neighbor_id, strategy, expected_reward))
    |> List.filter_opt
  
  (** Select best neighbor based on expected rewards and strategies *)
  let select_delegatee _t ~agent:_ ~strategies =
    (* m ← argmax_{j∈ad_i}(r_{i,j}) *)
    List.max_elt strategies ~compare:(fun (_, _, r1) (_, _, r2) ->
      Float.compare r1 r2)
  
  (** Check if strategy satisfies ε-equilibrium condition *)
  let check_equilibrium t ~strategy =
    (* 1-δ < x_{i,m} means state of nature favors delegation *)
    Float.(strategy > 1. -. t.delta)
  
  let decide t ~agent ~budget:_ =
    (* Compute strategies for all neighbors *)
    let strategies = compute_strategies t ~agent in
    
    if List.is_empty strategies then
      (* No neighbors, must execute *)
      (Action.Execute, t)
    else
      match select_delegatee t ~agent ~strategies with
      | None -> (Action.Execute, t)
      | Some (delegatee_id, strategy, expected_reward) ->
          if check_equilibrium t ~strategy then begin
            Agent.update_strategy agent
              ~reward_execute:(Agent.allocated_value agent)
              ~reward_delegate:expected_reward;
            (Action.Delegate delegatee_id, t)
          end else
            (Action.Execute, t)
  
  let learn t ~chain ~outcome =
    (* Update success/failure counters for all agents in chain *)
    List.iter chain ~f:(fun agent_id ->
      match Agent_registry.get t.registry agent_id with
      | None -> ()
      | Some agent ->
          if Float.(outcome > 0.) then
            Agent.increment_successes agent
          else
            Agent.increment_failures agent);
    t
  
  let execute t ~budget =
    let rec delegation_loop ~current_agent ~chain ~remaining_budget =
      let consumption = Agent.consumption_rate current_agent in
      
      if not (Resource.can_delegate ~budget:remaining_budget ~consumption) then
        (* Budget exhausted, force execution *)
        let reward = Agent.allocated_value current_agent in
        Agent.set_last_reward current_agent reward;
        (chain, reward, Equilibrium.Resolved {
          strategy = Agent.strategy current_agent;
          reward;
          epsilon = t.epsilon;
        })
      else
        let (action, _t') = decide t ~agent:current_agent ~budget:remaining_budget in
        let new_budget = Resource.consume ~budget:remaining_budget ~consumption in
        
        match action with
        | Execute ->
            let reward = Agent.allocated_value current_agent in
            Agent.set_last_reward current_agent reward;
            (chain, reward, Equilibrium.Resolved {
              strategy = Agent.strategy current_agent;
              reward;
              epsilon = t.epsilon;
            })
        
        | Delegate delegatee_id ->
            let delegatee = Agent_registry.get_exn t.registry delegatee_id in
            let extended_chain = chain @ [delegatee_id] in
            delegation_loop ~current_agent:delegatee ~chain:extended_chain ~remaining_budget:new_budget
        
        | Reject ->
            (* Task returns to delegator, forced execution *)
            let reward = Agent.allocated_value current_agent in
            Agent.set_last_reward current_agent reward;
            (chain, reward, Equilibrium.Resolved {
              strategy = Agent.strategy current_agent;
              reward;
              epsilon = t.epsilon;
            })
    in
    
    (* Start from root *)
    match Agent_registry.get t.registry Agent_id.root with
    | None -> failwith "Root agent not found"
    | Some root ->
        let initial_chain = [Agent_id.root] in
        delegation_loop ~current_agent:root ~chain:initial_chain ~remaining_budget:budget
end
