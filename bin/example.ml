(** Example: Compare DIG vs DEC performance.
    
    Runs both protocols under identical conditions and compares:
    - Probability of Successful Delegation (PSD)
    - Resource efficiency (E/R ratio)
    - Cumulative regret
    
    Demonstrates theoretical claim:
    - DIG: higher rewards but resource-intensive (hierarchical extraction)
    - DEC: lower rewards but more sustainable (cooperative resistance)
*)

open Core
open Delegation_games

let run_comparison () =
  printf "=== Delegation Games: Protocol Comparison ===\n\n";
  
  (* Set up parameters *)
  let params = Simulation.Sim_params.paper_default "comparison" in
  
  (* Reduce scale for demonstration *)
  let demo_params = {
    params with
    num_trials = 100;
    num_runs = 10;
  } in
  
  printf "Running with:\n";
  printf "  Trials: %d, Runs: %d\n" demo_params.num_trials demo_params.num_runs;
  printf "  Budget: [%.0f, %.0f]\n" 
    (fst demo_params.budget_range) (snd demo_params.budget_range);
  printf "  Value: [%.0f, %.0f]\n\n" 
    (fst demo_params.value_range) (snd demo_params.value_range);
  
  (* Run DIG *)
  let dig_result =
    Simulation.Simulation.run
      ~params:demo_params
      ~protocol_module:(module Protocol_dig.DIG : Protocol_dig.PROTOCOL)
      ~protocol_name:"DIG"
  in

  Simulation.Simulation.print_summary dig_result;

  (* Run DEC *)
  let dec_result =
    Simulation.Simulation.run
      ~params:demo_params
      ~protocol_module:(module Protocol_dec.DEC : Protocol_dig.PROTOCOL)
      ~protocol_name:"DEC"
  in
  
  Simulation.Simulation.print_summary dec_result;
  
  (* Comparative analysis *)
  printf "=== Comparative Analysis ===\n";
  printf "DIG vs DEC:\n";
  printf "  PSD difference: %.3f\n" 
    (dig_result.mean_psd -. dec_result.mean_psd);
  printf "  Reward difference: %.2f\n" 
    (dig_result.mean_reward -. dec_result.mean_reward);
  printf "  Regret difference: %.2f\n" 
    (dig_result.mean_regret -. dec_result.mean_regret);
  printf "\n";
  
  (* Theoretical interpretation *)
  printf "Theoretical interpretation:\n";
  if Float.(dig_result.mean_psd > dec_result.mean_psd) then
    printf "  DIG achieves higher PSD (hierarchical extraction more \"successful\")\n";
  if Float.(dig_result.mean_reward > dec_result.mean_reward) then
    printf "  DIG captures more value (surplus flows upward)\n";
  
  let dig_efficiency = 
    dig_result.mean_reward /. 
    (List.hd_exn dig_result.runs).total_expenditure
  in
  let dec_efficiency = 
    dec_result.mean_reward /. 
    (List.hd_exn dec_result.runs).total_expenditure
  in
  
  if Float.(dec_efficiency > dig_efficiency) then
    printf "  DEC is more resource-efficient (cooperative sustainability)\n";
  
  printf "\n"

let () = run_comparison ()
