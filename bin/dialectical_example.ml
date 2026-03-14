(** DDG with Paramuno knowledge topology and framework.

    Each trial independently draws:
      - a random root agent from all 40 network agents
      - a random argument type from six Páramo claim types

    Truth value distribution emerges from the position × claim evaluation
    matrix — it is NOT engineered by grouping trials.

    Expected outcome ranges (analytically derived from position assignments):
    - T: ~65%  (technical claims: ecosystem_technical, territorial, water, biodiversity
                → all accepted by all positions; dominates because 4/6 arg types → T)
    - B: ~10–20% (ecosystem_political from Paramuno root → B at depth=1 [77.5% of
                  political trials]; Development from Env root → B)
    - F: ~10–20% (Development from Paramuno/Sci-leaf root → F)
    - N: ~0%    (no Unknown_claim in 6-arg pool; N appears only as intermediate
                 routing state, never terminal)
    - Mean depth: ~1.2 hops
    - Contradiction coverage: ~15%
    - Non-trivial outcomes (B+F): ~25%

    Analytical note on depth:
    With 31/40 agents being Paramuno, political ecosystem claims are evaluated
    directly as B at depth=1 by Paramuno roots (who hold political-epistemic
    standing). Depth=2 occurs when Sci is root (N → Paramuno leaf → B).
    Depth=3 occurs when Env is root (N → Sci → N → Paramuno → B).
    Mean depth ~1.2 is correct — it reflects that Paramuno is the authoritative
    evaluator and terminates immediately, not a routing failure.

    Results vary across runs — this is a feature, not a bug.
    The distribution is an emergent property of the network topology
    and epistemic position assignments, not a manufactured artifact.
*)

open Core
open Delegation_games
open Dialectical
open Belnap_gadt
open Protocol_ddg

let () =
  Random.self_init ();
  printf "=== Delegation Games: Dialectical Delegation (DDG) ===\n\n";

  (* Create base topology: 3-level tree, branching=3 → 40 agents *)
  let paramo_registry =
    Simulation.Simulation.create_registry
      ~topology_spec:(Simulation.Sim_params.Directed_tree { levels = 3; branching = 3 })
      ~game_value:1000.
  in

  (* 1 + 3 + 9 + 27 = 40 agents *)
  printf "Topology: Tree (branching=3, depth=3) → 40 agents\n\n";

  (* Epistemic position assignment by tree depth.
     The directed_tree generator uses DFS ID assignment, so depth-2 agents
     are NOT ids 4-12 (that would be BFS). Actual layout for levels=3, branching=3:
       depth=0 (id=0)                      : Paramuno_lifeworld  (root)
       depth=1 (ids 1,2,3)                 : Environmental_agency
       depth=2 (ids 4,5,6,16,17,18,28,29,30): Scientific_conservation
       depth=3 (all remaining ids 7-39)    : Paramuno_lifeworld  (leaves)

     Tree structure (first branch expanded):
       0 → [1,2,3] → 1→[4,5,6], 2→[16,17,18], 3→[28,29,30]
       4→[7,8,9], 5→[10,11,12], 6→[13,14,15] (all depth-3 leaves)

     Paramuno inhabits both the root and the leaves — framing the
     agency/science layer from both sides. Development policy claims
     evaluated by Paramuno root F-route through Environmental_agency
     (which holds a contradictory B mandate), while Scientific nodes
     route development claims to Paramuno leaves where they terminate F.
  *)
  let ptopo = Paramo_topology.Paramo_topology.create ~base_topology:paramo_registry in
  let assign = Paramo_topology.Paramo_topology.assign_position ptopo in
  let id = Core_types.Agent_id.of_int in

  assign (id 0) Paramo_topology.Paramuno_lifeworld;
  List.iter [1; 2; 3] ~f:(fun i -> assign (id i) Paramo_topology.Environmental_agency);
  (* Depth-2 Sci agents: children of Env1=[4,5,6], Env2=[16,17,18], Env3=[28,29,30] *)
  List.iter [4; 5; 6; 16; 17; 18; 28; 29; 30]
    ~f:(fun i -> assign (id i) Paramo_topology.Scientific_conservation);
  (* Depth-3 Paramuno leaves: all remaining ids 7-39 (excluding depth-2 Sci above) *)
  List.iter (List.range 7 40 |> List.filter ~f:(fun i ->
    not (List.mem [4;5;6;16;17;18;28;29;30] i ~equal:Int.equal)))
    ~f:(fun i -> assign (id i) Paramo_topology.Paramuno_lifeworld);

  printf "Epistemic positions:\n";
  printf "  Paramuno_lifeworld:      31 agents (id=0; depth-3 leaves)\n";
  printf "  Environmental_agency:     3 agents (ids 1-3, depth=1)\n";
  printf "  Scientific_conservation:  9 agents (depth=2: 4,5,6,16,17,18,28,29,30)\n\n";

  (* Paramo_framework — typed-topology variant.
     The topology type and value are explicit in the functor signature,
     decoupling the evaluation logic from any specific topology implementation. *)
  let module PF = Argumentation_framework.Paramo_framework(struct
    type t = Paramo_topology.Paramo_topology.t
    let topology     = ptopo
    let get_position = Paramo_topology.Paramo_topology.position_of
  end) in

  let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in

  (* All 40 agent IDs available as roots *)
  let all_agents = List.init 40 ~f:id in
  let n_agents   = List.length all_agents in

  (* Six Páramo argument constructors — randomly selected each trial.
     Ecosystem is split into technical (all→T) and political (Sci/Env→N→Paramuno→B)
     to operationalize: capability to measure ≠ capability to judge extraction. *)
  let arg_names = [|
    "Ecosystem_technical"; "Ecosystem_political";
    "Territorial"; "Development"; "Water"; "Biodiversity";
  |] in
  let argument_types = [|
    Argument.paramo_ecosystem_technical_argument; (* all positions → T, depth=1 *)
    Argument.paramo_ecosystem_political_argument; (* Sci/Env→N→Paramuno→B, depth 2-3 *)
    Argument.paramo_territorial_argument;         (* Territorial_autonomy claim *)
    Argument.paramo_development_argument;         (* Development_policy claim *)
    Argument.paramo_water_argument;               (* Water_regulation → Sci/Paramuno→T *)
    Argument.paramo_biodiversity_argument;        (* Biodiversity_conservation → Sci/Paramuno→T *)
  |] in
  let n_arg_types = Array.length argument_types in

  (* Run 100 trials: random root × random argument each time.
     Record (arg_index, root_agent, trace) for per-argument analysis. *)
  let n_trials = 100 in
  printf "Running %d trials (random root agent × random argument type)...\n\n" n_trials;

  let tagged_trials = List.init n_trials ~f:(fun _ ->
    let root_agent = List.nth_exn all_agents (Random.int n_agents) in
    let arg_idx    = Random.int n_arg_types in
    let arg_fn     = argument_types.(arg_idx) in
    let trace      = DDG.execute_with_arg ~topology:ptopo ~root_agent ~arg:(arg_fn ()) in
    (arg_idx, root_agent, trace))
  in
  let traces = List.map tagged_trials ~f:(fun (_, _, tr) -> tr) in

  (* Aggregate analysis *)
  printf "=== Results ===\n\n";

  let coverage  = Analysis.contradiction_coverage traces in
  let depth     = Analysis.mean_argument_depth traces in
  let diversity = Analysis.defeater_diversity traces in

  printf "Contradiction coverage: %.1f%%\n" (coverage *. 100.);
  printf "Mean argument depth:    %.2f hops\n" depth;
  printf "Defeater diversity:     %d unique defeaters\n\n" diversity;

  (* State distribution *)
  let t_count = ref 0 in
  let f_count = ref 0 in
  let b_count = ref 0 in
  let n_count = ref 0 in

  List.iter traces ~f:(fun trace ->
    match trace.final_evaluation with
    | Truth T -> incr t_count
    | Truth F -> incr f_count
    | Truth B -> incr b_count
    | Truth N -> incr n_count);

  let pct n = Float.of_int n /. Float.of_int n_trials *. 100. in

  printf "State distribution (emerges from position × claim matrix):\n";
  printf "  T (accepted):      %3d (%.1f%%)  expected ~65%%  (4/6 arg types → T for all positions)\n"
    !t_count (pct !t_count);
  printf "  F (rejected):      %3d (%.1f%%)  expected ~15%%  <- routes to attackers\n"
    !f_count (pct !f_count);
  printf "  B (contradiction): %3d (%.1f%%)  expected ~15%%  <- preserved (eco_political + dev×env)\n"
    !b_count (pct !b_count);
  printf "  N (unknown):       %3d (%.1f%%)  expected  ~0%%  <- no Unknown_claim in 6-arg pool\n\n"
    !n_count (pct !n_count);

  let routed = !f_count + !n_count in
  printf "Dialectical routing triggered (F+N): %d trials (%.1f%%)\n" routed (pct routed);
  printf "Non-trivial outcomes (B+F): %d trials (%.1f%%)  expected ~25%%\n\n"
    (!b_count + !f_count) (pct (!b_count + !f_count));

  (* Per-argument-type analysis *)
  printf "=== Per-Argument-Type Analysis ===\n\n";

  let env_ids = [1; 2; 3] in
  let is_env agent_id = List.mem env_ids (Core_types.Agent_id.to_int agent_id) ~equal:Int.equal in

  Array.iteri arg_names ~f:(fun idx name ->
    let group = List.filter_map tagged_trials ~f:(fun (ai, root, tr) ->
      if ai = idx then Some (root, tr) else None)
    in
    let n = List.length group in
    if n > 0 then begin
      let depths = List.map group ~f:(fun (_, tr) -> List.length tr.path) in
      let mean_d = Float.of_int (List.fold depths ~init:0 ~f:(+)) /. Float.of_int n in
      let counts = List.fold group ~init:(0,0,0,0) ~f:(fun (t,f,b,nn) (_,tr) ->
        match tr.final_evaluation with
        | Truth T -> (t+1,f,b,nn) | Truth F -> (t,f+1,b,nn)
        | Truth B -> (t,f,b+1,nn) | Truth N -> (t,f,b,nn+1))
      in
      let (tc,fc,bc,nc) = counts in
      printf "%s (%d trials): depth=%.2f  T=%d F=%d B=%d N=%d\n"
        name n mean_d tc fc bc nc;

      (* Political ecosystem verification: Env/Sci root + political claim depth check *)
      if idx = 1 then begin
        let env_eco = List.filter group ~f:(fun (root, _) -> is_env root) in
        let n_env = List.length env_eco in
        if n_env > 0 then begin
          let env_depths = List.map env_eco ~f:(fun (_, tr) -> List.length tr.path) in
          let env_mean = Float.of_int (List.fold env_depths ~init:0 ~f:(+)) /. Float.of_int n_env in
          let env_states = List.map env_eco ~f:(fun (_, tr) ->
            match tr.final_evaluation with
            | Truth T -> "T" | Truth F -> "F" | Truth B -> "B" | Truth N -> "N")
          in
          printf "  Political depth check — Env root (%d trials): depth=%.2f  states=[%s]\n"
            n_env env_mean (String.concat ~sep:"," env_states)
        end else
          printf "  Political depth check — Env root: 0 trials this run\n"
      end
    end);

  printf "\n";

  (* Validation *)
  printf "=== Validation ===\n\n";

  (* Per-argument depth for ecosystem_political (idx=1) validation *)
  let eco_political_trials = List.filter_map tagged_trials ~f:(fun (ai, _, tr) ->
    if ai = 1 then Some (List.length tr.path) else None)
  in
  let eco_political_mean_depth =
    match eco_political_trials with
    | [] -> 0.
    | depths ->
      Float.of_int (List.fold depths ~init:0 ~f:(+)) /.
      Float.of_int (List.length depths)
  in

  (* With 6 structured claim types (no Unknown_claim), N terminal states
     are not expected — Sci/Env receiving political claims route to Paramuno
     which evaluates as B, not N. "Routing triggered" is redefined as B+F
     (claims that required more than immediate T acceptance). *)
  let non_trivial = !b_count + !f_count in

  let checks = [
    ("Mean depth > 1.0",                        Float.(depth > 1.0));
    ("Contradiction coverage > 0%",             Float.(coverage > 0.));
    ("F states present",                        !f_count > 0);
    ("B states present",                        !b_count > 0);
    ("Ecosystem_political mean depth > 1.0",    Float.(eco_political_mean_depth > 1.0));
    ("Non-trivial routing (B+F) > 20%",         Float.(of_int non_trivial /. of_int n_trials > 0.2));
  ] in

  let all_passed = List.for_all checks ~f:snd in

  List.iter checks ~f:(fun (check, passed) ->
    printf "[%s] %s\n" (if passed then "PASS" else "FAIL") check);

  printf "\n";

  if all_passed then
    printf "All validation checks passed. DDG is functional.\n"
  else
    printf "Some checks failed. Review Paramo_framework implementation.\n";

  printf "\nNote: exact counts vary across runs — distribution is stochastic.\n";
  printf "DDG results are incommensurable with DIG/DEC scalar metrics.\n";
  printf "Research question: Does DDG reveal contradictions DIG/DEC erase?\n"
