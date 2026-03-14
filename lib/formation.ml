(** Coalition formation - constructing delegation chains via myopic lookahead.
    
    Algorithm 1 from paper: agents form coalitions by:
    1. Selecting immediate neighbor (delegatee)
    2. Looking ahead to neighbor's neighbors (2-hop)
    3. Potentially including one more level (3-hop)
    4. Length sampled from U(2,3) to model bounded rationality
    
    Theoretical commitment: myopia as constitutive of agency.
    Agents don't have global view - they can only foresee 2-3 hops ahead.
    This is NOT a computational limitation but an ontological claim:
    agency is fundamentally local and limited.
    
    Implementation allows making this adaptive: max_length could depend on
    resources, network position, or learning history. But default is fixed
    theoretical commitment to myopic horizon = 3.
*)

open Core
open Core_types
open Agent

module Formation_params = struct
  type t = {
    min_length: int;  (* minimum coalition size, typically 2 *)
    max_length: int;  (* maximum coalition size, typically 3 *)
    adaptive: bool;   (* whether to make length depend on context *)
  }
  
  let default = {
    min_length = 2;
    max_length = 3;
    adaptive = false;
  }
  
  (** Sample coalition length from U(min, max) *)
  let sample_length t =
    if t.min_length >= t.max_length then
      t.max_length
    else
      t.min_length + Random.int (t.max_length - t.min_length + 1)
  
  (** Adaptive length: reduce max_length as resources deplete *)
  let adaptive_length t ~remaining_budget ~initial_budget =
    if not t.adaptive then sample_length t
    else
      let budget_ratio = remaining_budget /. initial_budget in
      if Float.(budget_ratio < 0.3) then
        t.min_length  (* conserve resources when depleted *)
      else if Float.(budget_ratio < 0.6) then
        (t.min_length + t.max_length) / 2
      else
        sample_length t
end

(** Coalition formation algorithm.
    
    Input: delegator agent, registry for neighbor lookup, formation params
    Output: delegation chain (potential coalition)
    
    Procedure:
    1. Select delegatee from immediate neighbors
    2. Recursively add delegatee's neighbors until length limit
    3. Ensure no cycles (same agent doesn't appear twice)
*)
module Formation = struct
  (** Build coalition recursively via neighbor exploration *)
  let rec build_chain 
      ~registry 
      ~current_agent 
      ~target_length 
      ~chain_so_far =
    
    (* Base case: reached target length or current_agent has no neighbors *)
    if Delegation_chain.length chain_so_far >= target_length then
      chain_so_far
    else
      let neighbors = Agent_registry.get_neighbors registry current_agent in
      
      (* Filter out neighbors already in chain (prevent cycles) *)
      let available_neighbors = 
        List.filter neighbors ~f:(fun neighbor_id ->
          not (List.mem chain_so_far neighbor_id ~equal:Agent_id.equal))
      in
      
      match available_neighbors with
      | [] -> chain_so_far  (* no available neighbors, return current chain *)
      | _ ->
          (* Sample random neighbor *)
          let next_agent_id = 
            List.nth_exn available_neighbors 
              (Random.int (List.length available_neighbors))
          in
          
          let next_agent = Agent_registry.get_exn registry next_agent_id in
          let extended_chain = chain_so_far @ [next_agent_id] in
          
          (* Recursively build from next agent *)
          build_chain
            ~registry
            ~current_agent:next_agent
            ~target_length
            ~chain_so_far:extended_chain
  
  (** Form coalition starting from delegator.
      
      Returns: potential delegation chain for Shapley/Myerson computation.
      
      Note: this is called "coalition formation" but produces an ordered chain.
      The coalition semantics emerge when we compute Shapley values -
      the order doesn't matter for marginal contributions.
  *)
  let form_coalition
      ~delegator
      ~registry
      ~params
      ?(budget_info=None)
      () =
    
    let target_length = 
      match budget_info with
      | None -> Formation_params.sample_length params
      | Some (remaining, initial) ->
          Formation_params.adaptive_length params 
            ~remaining_budget:remaining
            ~initial_budget:initial
    in
    
    (* Chain starts with delegator *)
    let initial_chain = [Agent.id delegator] in
    
    (* Build chain recursively *)
    let chain = 
      build_chain
        ~registry
        ~current_agent:delegator
        ~target_length
        ~chain_so_far:initial_chain
    in
    
    (* Validate chain *)
    if Delegation_chain.is_valid ~max_length:params.max_length chain then
      Some chain
    else
      None
  
  (** Form multiple alternative coalitions for comparison.
      
      DEC algorithm computes Shapley values across different possible coalitions,
      then selects delegatee who makes largest contribution.
      
      This generates k alternative coalitions by:
      - Sampling different random neighbors at each step
      - Varying coalition length within [min_length, max_length]
      
      Returns: list of (coalition, terminal_agent) pairs
  *)
  let form_alternatives
      ~delegator
      ~registry
      ~params
      ?(k=5)
      ?(budget_info=None)
      () =
    
    List.init k ~f:(fun _ ->
      form_coalition ~delegator ~registry ~params ~budget_info ())
    |> List.filter_opt
    |> List.map ~f:(fun chain ->
        let terminal = Delegation_chain.terminal chain in
        (chain, terminal))
end

(** Coalition evaluation - compute expected value of coalition formation.
    
    Given:
    - Potential coalition (delegation chain)
    - Characteristic function (learned from past)
    - Solution concept (Shapley or Myerson)
    
    Compute:
    - Marginal contribution of each agent
    - Expected reward from forming this coalition
    
    This is used in DEC to select among alternative coalitions.
*)
module Evaluation = struct
  (** Compute expected rewards for all agents in coalition.
      
      Uses Shapley/Myerson to attribute collective value to individuals.
      Returns map: agent_id -> expected_reward
  *)
  let compute_contributions
      ~coalition_chain
      ~char_func
      ~solution_concept
      ~registry =
    
    let get_neighbors id =
      match Agent_registry.get registry id with
      | None -> []
      | Some agent -> Agent.neighbors agent
    in
    
    List.map coalition_chain ~f:(fun agent_id ->
      let contribution = 
        Coalition.Solution_concept.compute
          solution_concept
          char_func
          agent_id
          coalition_chain
          ~get_neighbors
      in
      (agent_id, contribution))
    |> Map.of_alist_exn (module Agent_id)
  
  (** Select best delegatee based on marginal contributions.
      
      DEC algorithm (line 5): m ← argmax_{i∈adj_k} (my_i)
      
      Returns: agent who makes largest marginal contribution to coalition.
  *)
  let select_delegatee
      ~alternatives
      ~char_func  
      ~solution_concept
      ~registry =
    
    List.map alternatives ~f:(fun (chain, terminal_opt) ->
      match terminal_opt with
      | None -> None
      | Some terminal_id ->
          let contributions = 
            compute_contributions
              ~coalition_chain:chain
              ~char_func
              ~solution_concept
              ~registry
          in
          
          (* Get contribution of terminal agent (potential delegatee) *)
          Map.find contributions terminal_id
          |> Option.map ~f:(fun contribution ->
              (terminal_id, contribution, chain)))
    |> List.filter_opt
    |> List.max_elt ~compare:(fun (_, contrib1, _) (_, contrib2, _) ->
        Float.compare contrib1 contrib2)
end
