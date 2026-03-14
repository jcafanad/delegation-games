(** Benchmark sequential vs parallel Shapley computation.

    Run: dune exec test/bench_parallel.exe

    Validates:
    1. Sequential and Parallel produce identical results (within tolerance)
    2. Parallel achieves speedup on sufficiently large inputs
    3. No race conditions or unexpected errors

    Phase 3 prerequisite: only proceed with parallel Shapley if this
    benchmark shows >2x speedup for your realistic input sizes AND
    Shapley is consuming >30% of total runtime.
*)

open Core
open Delegation_games
open Core_types
open Coalition

(** Compute absolute difference between floats *)
let float_diff a b = Float.abs (a -. b)

(** Build a simple characteristic function with random values for benchmarking *)
let build_char_func agents =
  let cf = Characteristic_function.create () in
  let all_coalitions = Coalition.power_set (Coalition.of_chain agents) in
  List.fold all_coalitions ~init:cf ~f:(fun acc coalition ->
    let value = Random.float 100. in
    Characteristic_function.update acc coalition value)

(** Time a function in milliseconds *)
let time_ms f =
  let t0 = Core_unix.gettimeofday () in
  let result = f () in
  let elapsed_ms = (Core_unix.gettimeofday () -. t0) *. 1000. in
  (result, elapsed_ms)

(** Benchmark both implementations and check correctness *)
let benchmark_shapley n_agents =
  let agents = List.init n_agents ~f:(fun i -> Agent_id.of_int i) in
  let char_func = build_char_func agents in
  let agent = List.hd_exn agents in

  let module Seq = Coalition_parallel.Sequential in
  let module Par = Coalition_parallel.Parallel in

  let (seq_val, seq_ms) = time_ms (fun () ->
    Seq.value ~char_func ~agent ~all_agents:agents) in

  let (par_val, par_ms) = time_ms (fun () ->
    Par.value ~char_func ~agent ~all_agents:agents) in

  let diff = float_diff seq_val par_val in
  let speedup = seq_ms /. par_ms in

  printf "n=%2d  seq=%.3fms  par=%.3fms  speedup=%.2fx  diff=%.2e  %s\n"
    n_agents seq_ms par_ms speedup diff
    (if Float.(diff < 0.001) then "OK" else "MISMATCH!")

(** Validate marginal contributions are identical between implementations *)
let validate_marginals n_agents =
  let agents = List.init n_agents ~f:(fun i -> Agent_id.of_int i) in
  let char_func = build_char_func agents in
  let agent = List.hd_exn agents in
  let all_coalitions = Coalition.power_set (Coalition.of_chain agents) in
  let containing = List.filter all_coalitions ~f:(fun c -> Coalition.mem c agent) in

  let module Seq = Coalition_parallel.Sequential in
  let module Par = Coalition_parallel.Parallel in

  let seq_results = Seq.marginal_contributions ~char_func ~agent ~coalitions:containing in
  let par_results = Par.marginal_contributions ~char_func ~agent ~coalitions:containing in

  let all_match = List.for_all2_exn seq_results par_results
    ~f:(fun (_, sv) (_, pv) -> Float.(abs (sv -. pv) < 0.001))
  in
  printf "n=%2d marginals: %d coalitions — %s\n"
    n_agents (List.length containing)
    (if all_match then "MATCH" else "MISMATCH!")

let () =
  Random.self_init ();
  printf "\n=== Parallel Shapley Benchmark (Phase 3 validation) ===\n\n";

  printf "Timing comparison (seq vs par):\n";
  List.iter [5; 8; 10; 12] ~f:benchmark_shapley;

  printf "\nMarginal contribution correctness:\n";
  List.iter [5; 8; 10] ~f:validate_marginals;

  printf "\nNote: current Parallel module delegates to Sequential.\n";
  printf "Phase 3 gate: >2x speedup requires OCaml 5.x Domain.spawn.\n";
  printf "Run `DELEGATION_PARALLEL=true` to use Parallel implementation.\n"
