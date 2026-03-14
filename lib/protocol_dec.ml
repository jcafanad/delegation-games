(** DEC Protocol - Coalitional Delegation Implementation.
    
    Algorithm 2 from paper (Algorithm 2: Delegation Game of Coalitions Under Myerson):
    
    function DEC(K, V; {s_k}):
      INIT_DEC(K, V)
      while Constraint ≥ Consumption:
        for j=1 → n:
          (m, r_m, S_j) ← DEL(P_j, s_j)
          if s_m > 1-δ:
            α_j ← α_j + 1
            Consumption ← Consumption + 1/(α_m+β_m)
          else:
            β_j ← β_j + 1  
            Consumption ← Consumption + 1/(α_j+β_j)
          Update outcomes
          S ← S_j ∪ {S_j}
          ν ← ν ∪ {Σ_{k∈D_j} r_k}
        Constraint ← Constraint - Consumption
      return (S, ν)
    
    function DEL(P_k):
      coalition ← CForm(k)
      D_k ← D_k ∪ {coalition}
      my_k ← My_k(|D_k|; Σ_{i∈D_k} r_i)
      m ← argmax_{i∈ad_k}(my_i)
      S_k ← S_k ∪ {a_m}
      if m ≠ k:
        return DEL(P_m, s_m)
      else:
        r_m ← o_m
      return (m, r_m, S_k)
*)

open Core
open Core_types
open Agent
open Coalition
open Formation
open Protocol_dig

module DEC : PROTOCOL = struct
  type t = {
    registry: Agent_registry.t;
    char_func: Characteristic_function.t;
    solution_concept: Solution_concept.t;
    formation_params: Formation_params.t;
    delta: float;
    
    (* Track coalitions formed per agent for Myerson computation *)
    coalitions_formed: (Agent_id.t, Coalition.t list) Hashtbl.t;
  }
  
  let name = "DEC"
  
  let create ~registry ~params =
    let delta = 
      Map.find params "delta"
      |> Option.map ~f:Float.of_string
      |> Option.value ~default:0.1
    in
    
    let max_coalition_length =
      Map.find params "max_coalition_length"
      |> Option.map ~f:Int.of_string
      |> Option.value ~default:3
    in
    
    let adaptive =
      Map.find params "adaptive_coalitions"
      |> Option.map ~f:Bool.of_string
      |> Option.value ~default:false
    in
    
    {
      registry;
      char_func = Characteristic_function.create ();
      solution_concept = Solution_concept.of_topology registry.topology;
      formation_params = { 
        min_length = 2; 
        max_length = max_coalition_length;
        adaptive 
      };
      delta;
      coalitions_formed = Hashtbl.create (module Agent_id);
    }
  
  (** DEL function - recursive delegation with coalition formation *)
  let rec delegate t ~agent ~budget ~budget_info =
    let agent_id = Agent.id agent in
    
    (* CForm: form potential coalitions *)
    let alternatives = 
      Formation.form_alternatives
        ~delegator:agent
        ~registry:t.registry
        ~params:t.formation_params
        ~k:5
        ~budget_info:(Some budget_info)
        ()
    in
    
    if List.is_empty alternatives then
      (* No coalitions possible, execute *)
      (Action.Execute, t, [agent_id])
    else
      (* Track coalitions for this agent *)
      let coalitions = 
        List.map alternatives ~f:(fun (chain, _) -> Coalition.of_chain chain)
      in
      Hashtbl.set t.coalitions_formed ~key:agent_id ~data:coalitions;
      
      (* Select best delegatee via Shapley/Myerson *)
      let selection = 
        Evaluation.select_delegatee
          ~alternatives
          ~char_func:t.char_func
          ~solution_concept:t.solution_concept
          ~registry:t.registry
      in
      
      match selection with
      | None -> (Action.Execute, t, [agent_id])
      | Some (delegatee_id, _contribution, chain) ->
          (* Check if state of nature favors delegation *)
          let delegatee = Agent_registry.get_exn t.registry delegatee_id in
          let success_prob = 
            let total = Agent.successes delegatee + Agent.failures delegatee in
            if total = 0 then 0.5
            else Float.of_int (Agent.successes delegatee) /. Float.of_int total
          in
          
          if Float.(success_prob > 1. -. t.delta) then
            (* Delegate further if delegatee is not terminal *)
            if Agent_id.equal delegatee_id agent_id then
              (* Self-loop, execute *)
              (Action.Execute, t, chain)
            else
              (* Recursively delegate *)
              let (action, t', extended_chain) = 
                delegate t ~agent:delegatee ~budget ~budget_info
              in
              (action, t', chain @ (List.tl_exn extended_chain))
          else
            (* Execute at current agent *)
            (Action.Execute, t, chain)
  
  let decide t ~agent ~budget =
    let remaining = budget in
    let initial = budget in
    let (action, t', _) = 
      delegate t ~agent ~budget ~budget_info:(remaining, initial)
    in
    (action, t')
  
  (** Learn from delegation outcome - update characteristic function *)
  let learn t ~chain ~outcome =
    (* Compute rewards for each agent in chain using distribution rule *)
    let coalition_size = List.length chain in
    let rewards = 
      List.mapi chain ~f:(fun position agent_id ->
        let reward = 
          Value.distribute_reward 
            ~outcome 
            ~position:(position + 1)
            ~coalition_size
        in
        (agent_id, reward))
    in
    
    (* Update characteristic function with total coalition value *)
    let total_value = 
      List.sum (module Float) rewards ~f:(fun (_, r) -> r)
    in
    let coalition = Coalition.of_chain chain in
    let char_func' = 
      Characteristic_function.update t.char_func coalition total_value
    in
    
    (* Set rewards for agents *)
    List.iter rewards ~f:(fun (agent_id, reward) ->
      match Agent_registry.get t.registry agent_id with
      | None -> ()
      | Some agent -> Agent.set_last_reward agent reward);
    
    { t with char_func = char_func' }
  
  let execute t ~budget =
    let rec delegation_loop ~current_agent ~chain ~remaining_budget ~initial_budget =
      let consumption = Agent.consumption_rate current_agent in
      
      if not (Resource.can_delegate ~budget:remaining_budget ~consumption) then
        (* Budget exhausted *)
        let outcome = Agent.allocated_value current_agent in
        let _t' = learn t ~chain ~outcome in
        (chain, outcome, Equilibrium.Resolved {
          strategy = 0.;
          reward = outcome;
          epsilon = 0.01;
        })
      else
        let budget_info = (remaining_budget, initial_budget) in
        let (action, t', sub_chain) = 
          delegate t ~agent:current_agent ~budget:remaining_budget ~budget_info
        in
        let new_budget = Resource.consume ~budget:remaining_budget ~consumption in
        
        match action with
        | Execute ->
            (* Sample outcome and distribute rewards *)
            let allocation = Agent.allocated_value current_agent in
            let outcome = 
              Value.sample_outcome 
                ~allocation 
                ~game_value:t.registry.game_value
            in
            
            (* Update successes *)
            Agent.increment_successes current_agent;
            
            (* Learn from this delegation chain *)
            let _t'' = learn t' ~chain:sub_chain ~outcome in
            
            (sub_chain, outcome, Equilibrium.Resolved {
              strategy = 0.;
              reward = outcome;
              epsilon = 0.01;
            })
        
        | Delegate delegatee_id ->
            let delegatee = Agent_registry.get_exn t.registry delegatee_id in
            delegation_loop 
              ~current_agent:delegatee 
              ~chain:sub_chain
              ~remaining_budget:new_budget
              ~initial_budget
        
        | Reject ->
            let outcome = Agent.allocated_value current_agent in
            Agent.increment_failures current_agent;
            let _t'' = learn t' ~chain ~outcome in
            (chain, outcome, Equilibrium.Resolved {
              strategy = 0.;
              reward = outcome;
              epsilon = 0.01;
            })
    in
    
    (* Start from root *)
    match Agent_registry.get t.registry Agent_id.root with
    | None -> failwith "Root agent not found"
    | Some root ->
        let initial_chain = [Agent_id.root] in
        delegation_loop 
          ~current_agent:root 
          ~chain:initial_chain 
          ~remaining_budget:budget
          ~initial_budget:budget
end
