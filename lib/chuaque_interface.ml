(** Type-safe interface to chuaque paraconsistent logic module.

    Wraps Chuaque_ffi with GADT-typed atoms from Belnap_gadt.
    This allows delegation chains to be analyzed dialectically with
    compile-time guarantees about truth value types.

    Improvement over chuaque_ffi.ml (Phase 1.5):
    - Atoms carry GADT type tags (true_t, false_t, both_t, neither_t)
    - Chain-to-atom conversion uses oscillation state to assign truth values
    - Results lifted from simple Belnap.t to existential truth_val

    Phase 2 completes this by integrating with dialogue_effects.ml.
    The FFI call itself still uses subprocess/JSON (chuaque_ffi.ml).
    A native OCaml-Python bridge (ocaml-pyml) would replace this in production.
*)

open Core
open Core_types
open Agent
open Belnap_gadt

(** Typed atom: agent with GADT truth value for dialectical analysis *)
type 'a typed_atom = {
  agent       : Agent_id.t;
  proposition : string;
  valuation   : 'a truth;
}

(** Convert typed atom to untyped (for Chuaque_ffi) *)
let to_chuaque_atom : type a. a typed_atom -> Chuaque_ffi.atom =
  fun ta -> {
    Chuaque_ffi.agent      = Agent_id.to_int ta.agent;
    proposition = ta.proposition;
    valuation   = to_simple ta.valuation;
  }

(** Existential wrapper for heterogeneous typed atom lists *)
type any_typed_atom = AnyAtom : 'a typed_atom -> any_typed_atom

let pack_atom ta = AnyAtom ta

let unpack_chuaque (AnyAtom ta) = to_chuaque_atom ta

(** Build a typed atom for an agent given its action and truth classification.

    Called by the DDG protocol to assign truth values based on oscillation state.
    Caller is responsible for determining the truth value (is_oscillating → B, etc.)
*)
let action_to_typed_atom : type a.
    agent:Agent.t -> action:Action.t -> valuation:a truth -> a typed_atom =
  fun ~agent ~action ~valuation ->
    let proposition = match action with
      | Action.Execute        -> "executes_task"
      | Action.Delegate target ->
          sprintf "delegates_to_%d" (Agent_id.to_int target)
      | Action.Reject         -> "rejects_task"
    in
    { agent = Agent.id agent; proposition; valuation }

(** Classify delegation truth value using GADT types.

    Maps (oscillating × can_delegate) → Belnap GADT truth value:
    - (true,  true)  → B: contradiction (must AND cannot delegate)
    - (true,  false) → F: oscillating with no escape
    - (false, true)  → T: normal delegation
    - (false, false) → F: leaf node, cannot delegate

    Returns existential truth_val since result type depends on runtime state.
*)
let classify_delegation ~is_oscillating ~has_neighbors : truth_val =
  match (is_oscillating, has_neighbors) with
  | (true,  true)  -> Truth B   (* contradictory — B is designated *)
  | (true,  false) -> Truth F
  | (false, true)  -> Truth T
  | (false, false) -> Truth F

(** Build typed atoms for a complete delegation chain.

    For each agent in the chain, assigns a truth value based on:
    - Whether the chain is oscillating at this point
    - Whether the agent has available neighbors

    Returns: existential typed atoms (one per chain member).
*)
let chain_to_typed_atoms
    ~registry
    ~is_oscillating
    chain : any_typed_atom list =
  let n = List.length chain in
  List.filter_mapi chain ~f:(fun i agent_id ->
    match Agent_registry.get registry agent_id with
    | None -> None
    | Some agent ->
        let neighbors = Agent_registry.get_neighbors registry agent in
        let has_neighbors = not (List.is_empty neighbors) in
        let (Truth tv) = classify_delegation ~is_oscillating ~has_neighbors in
        let proposition =
          if i = n - 1 then
            "executes"  (* terminal agent *)
          else
            let next_id = List.nth_exn chain (i + 1) in
            sprintf "delegates_to_%d" (Agent_id.to_int next_id)
        in
        Some (AnyAtom { agent = agent_id; proposition; valuation = tv }))

(** Evaluate a delegation chain via chuaque with typed atoms.

    Builds typed atoms for the chain, calls Chuaque_ffi for dialectical evaluation,
    and lifts results to truth_val (existential).

    Returns:
    - Some truth_vals: one per atom, from chuaque analysis
    - None: chuaque unavailable or call failed (caller should use local evaluation)
*)
let evaluate_chain
    ~registry
    ~is_oscillating
    chain : truth_val list option =
  match Chuaque_ffi.evaluate_chain ~registry chain with
  | None ->
      (* chuaque unavailable — use local GADT classification for each agent *)
      let local_results =
        chain_to_typed_atoms ~registry ~is_oscillating chain
        |> List.map ~f:(fun (AnyAtom ta) -> Truth ta.valuation)
      in
      Some local_results
  | Some belnap_vals ->
      (* Lift chuaque Belnap results to existential truth_val *)
      Some (List.map belnap_vals ~f:of_simple)

(** Evaluate local delegation state without chuaque.

    Used when chuaque is unavailable or chain evaluation fails.
    Returns the GADT truth value for the current agent's delegation decision.
*)
let evaluate_local ~is_oscillating ~registry agent : truth_val =
  let neighbors = Agent_registry.get_neighbors registry agent in
  let has_neighbors = not (List.is_empty neighbors) in
  classify_delegation ~is_oscillating ~has_neighbors

(** Check if the evaluated chain contains any contradictory (B) atoms.
    Useful for triggering dialogue effects in DDG.
*)
let has_contradiction (results : truth_val list) : bool =
  List.exists results ~f:(fun (Truth tv) ->
    match is_contradictory tv with
    | Some Is_contradictory -> true
    | None -> false)
