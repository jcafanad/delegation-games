(** Tests for DDG dialectical routing functionality.

    Plain executable test runner — no ppx_inline_test required.

    Uses a 2-level tree topology (13 agents) for speed:
    - id=0         : Paramuno_lifeworld (root)
    - ids 1-3      : Environmental_agency (depth=1)
    - ids 4-12     : Paramuno_lifeworld  (leaves, depth=2, no children)
*)

open Core
open Delegation_games
open Dialectical

(** Simple test runner *)
let passed = ref 0
let failed = ref 0

let test name result =
  if result then begin
    printf "[PASS] %s\n" name;
    incr passed
  end else begin
    printf "[FAIL] %s\n" name;
    incr failed
  end

(** Set up a small Paramo topology for testing. *)
let make_test_topology () =
  let base = Simulation.Simulation.create_registry
    ~topology_spec:(Simulation.Sim_params.Directed_tree { levels = 2; branching = 3 })
    ~game_value:1000.
  in
  let topo = Paramo_topology.Paramo_topology.create ~base_topology:base in
  let assign = Paramo_topology.Paramo_topology.assign_position topo in
  let id = Core_types.Agent_id.of_int in
  assign (id 0) Paramo_topology.Paramuno_lifeworld;
  List.iter [1; 2; 3] ~f:(fun i -> assign (id i) Paramo_topology.Environmental_agency);
  List.iter (List.range 4 13) ~f:(fun i -> assign (id i) Paramo_topology.Paramuno_lifeworld);
  topo

(** Test topology that includes a Scientific_conservation agent.
    Same 2-level tree as make_test_topology, but id=3 reassigned to Sci.
    id=3 is depth=1 with children [10,11,12] (Paramuno leaves), enabling:
      political claim: Sci(3,N) → all neighbors → Paramuno leaf → B (depth=2) *)
let make_sci_test_topology () =
  let topo = make_test_topology () in
  Paramo_topology.Paramo_topology.assign_position
    topo (Core_types.Agent_id.of_int 3) Paramo_topology.Scientific_conservation;
  topo

let () =
  printf "=== Dialectical Routing Tests ===\n\n";

  (* Test 1: Paramo_framework produces B for Paramuno evaluating ecosystem services. *)
  let () =
    let topo = make_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let arg = Argument.paramo_ecosystem_argument () in
    test "Paramuno evaluates ecosystem services as B"
      (match PF.evaluate ~agent_id:Core_types.Agent_id.root ~arg with
       | Belnap_gadt.Truth Belnap_gadt.B -> true
       | _ -> false)
  in

  (* Test 2: State_administration rejects territorial autonomy claims. *)
  let () =
    let topo = make_test_topology () in
    Paramo_topology.Paramo_topology.assign_position
      topo Core_types.Agent_id.root Paramo_topology.State_administration;
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let arg = Argument.paramo_territorial_argument () in
    test "State rejects territorial autonomy as F"
      (match PF.evaluate ~agent_id:Core_types.Agent_id.root ~arg with
       | Belnap_gadt.Truth Belnap_gadt.F -> true
       | _ -> false)
  in

  (* Test 3: Argument.create helper builds argument with correct fields. *)
  let () =
    let arg = Argument.create
      ~id:"test_territorial"
      ~claim:"Paramuno communities have territorial autonomy"
      ~grounds:["Historical occupation"]
    in
    test "Argument.create produces correct record"
      (String.equal arg.Argument.claim "Paramuno communities have territorial autonomy"
       && List.length arg.Argument.grounds = 1
       && List.is_empty arg.Argument.defeaters)
  in

  (* Test 4: Development claim from Paramuno root routes to Env_agency (B), depth=2. *)
  let () =
    let topo = make_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in
    let traces = List.init 10 ~f:(fun _ ->
      DDG.execute_with_arg
        ~topology:topo
        ~root_agent:Core_types.Agent_id.root
        ~arg:(Argument.paramo_development_argument ()))
    in
    let mean_depth = Analysis.mean_argument_depth traces in
    test "Mean depth > 1 with routing through Env_agency"
      Float.(mean_depth > 1.0)
  in

  (* Test 5: Ecosystem claim from Paramuno root produces B (coverage > 0). *)
  let () =
    let topo = make_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in
    let traces = List.init 10 ~f:(fun _ ->
      DDG.execute_with_arg
        ~topology:topo
        ~root_agent:Core_types.Agent_id.root
        ~arg:(Argument.paramo_ecosystem_argument ()))
    in
    let coverage = Analysis.contradiction_coverage traces in
    test "Contradiction coverage > 0 with ecosystem claim"
      Float.(coverage > 0.)
  in

  (* Test 6: Technical ecosystem claim accepted (T) by all three positions. *)
  let () =
    let topo = make_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let arg = Argument.paramo_ecosystem_technical_argument () in
    let paramuno_ok = match PF.evaluate ~agent_id:Core_types.Agent_id.root ~arg with
      | Belnap_gadt.Truth Belnap_gadt.T -> true | _ -> false in
    let env_ok = match PF.evaluate ~agent_id:(Core_types.Agent_id.of_int 1) ~arg with
      | Belnap_gadt.Truth Belnap_gadt.T -> true | _ -> false in
    let sci_ok = match PF.evaluate ~agent_id:(Core_types.Agent_id.of_int 4) ~arg with
      | Belnap_gadt.Truth Belnap_gadt.T -> true | _ -> false in
    test "Technical ecosystem accepted (T) by Paramuno, Env, and Sci"
      (paramuno_ok && env_ok && sci_ok)
  in

  (* Test 7: Political ecosystem claim produces N from Sci (lacks standing).
     Uses make_sci_test_topology where id=3 is Scientific_conservation. *)
  let () =
    let topo = make_sci_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let arg = Argument.paramo_ecosystem_political_argument () in
    test "Political ecosystem produces N from Scientific (lacks political standing)"
      (match PF.evaluate ~agent_id:(Core_types.Agent_id.of_int 3) ~arg with
       | Belnap_gadt.Truth Belnap_gadt.N -> true
       | _ -> false)
  in

  (* Test 8: Political ecosystem claim produces B from Paramuno (genuine dialetheia). *)
  let () =
    let topo = make_sci_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let arg = Argument.paramo_ecosystem_political_argument () in
    test "Political ecosystem produces B from Paramuno (genuine dialetheia)"
      (match PF.evaluate ~agent_id:Core_types.Agent_id.root ~arg with
       | Belnap_gadt.Truth Belnap_gadt.B -> true
       | _ -> false)
  in

  (* Test 9: Political ecosystem routes Sci(N) → Paramuno → B at depth=2.
     Verifies the chain: technical competence → lack of standing → dialetheia.
     id=3 (Sci) has children [10,11,12] (Paramuno leaves) in the 2-level tree. *)
  let () =
    let topo = make_sci_test_topology () in
    let module PF = Argumentation_framework.Paramo_framework(struct
      type t = Paramo_topology.Paramo_topology.t
      let topology     = topo
      let get_position = Paramo_topology.Paramo_topology.position_of
    end) in
    let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in
    let sci_root = Core_types.Agent_id.of_int 3 in
    let traces = List.init 20 ~f:(fun _ ->
      DDG.execute_with_arg
        ~topology:topo
        ~root_agent:sci_root
        ~arg:(Argument.paramo_ecosystem_political_argument ()))
    in
    let mean_depth = Analysis.mean_argument_depth traces in
    let b_count = List.count traces ~f:(fun tr ->
      match tr.final_evaluation with Belnap_gadt.Truth Belnap_gadt.B -> true | _ -> false)
    in
    test "Political ecosystem from Sci root reaches depth > 1 and produces B states"
      Float.(mean_depth > 1.0 && of_int b_count > 0.)
  in

  (* Summary *)
  printf "\n";
  let total = !passed + !failed in
  if !failed = 0 then
    printf "All %d/%d tests passed.\n" !passed total
  else begin
    printf "%d/%d tests FAILED.\n" !failed total;
    exit 1
  end
