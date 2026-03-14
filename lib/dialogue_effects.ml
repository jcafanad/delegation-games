(** Effect handlers for dialectical dialogical games.

    Implements referee-mediated argumentation between proponent and opponent.
    Models argumentation as in Lorenzen-style dialogical logic:
    - Proponent (P) asserts claims
    - Opponent (O) challenges or requests defense
    - Referee enforces intentional logic rules

    On OCaml 5.x, this would use algebraic effects (Effect.t, Effect.Deep.match_with)
    for direct-style game execution. This implementation uses a callback-based approach
    for OCaml 4.x compatibility — the game semantics are identical.

    Integration with DDG:
    - Proponent asserts delegation claim (T or B)
    - Opponent checks for oscillation (challenges if B detected)
    - Referee decides if delegation proceeds
    - B assertions are VALID in paraconsistent logic (designated values)

    References:
    - Lorenzen, P. (1960). "Logik und Agon"
    - Rahman, S. & Keiff, L. (2005). "On how to be a dialogician"
*)

open Core
open Belnap_gadt

(** Dialogue outcome *)
type outcome =
  | Proponent_wins   (* claim accepted *)
  | Opponent_wins    (* claim rejected *)
  | Draw             (* max moves reached without resolution *)
[@@deriving sexp]

(** Proponent's move options *)
type proponent_move =
  | Assert of string * truth_val   (* assert atom with Belnap truth value *)
  | Withdraw of string             (* withdraw a previous assertion *)
  | Pass                           (* proponent is satisfied; done *)

(** Opponent's response options *)
type opponent_response =
  | Accept                         (* accept the assertion — proponent continues *)
  | Challenge of string            (* challenge specific atom *)
  | Request of string              (* request defense of previously asserted atom *)

(** Dialogue game state.
    Tracks assertions made, atoms challenged, and move count.
*)
type game_state = {
  assertions : (string, truth_val) Hashtbl.t;   (* atoms proponent has asserted *)
  challenged  : string Hash_set.t;               (* atoms opponent has challenged *)
  mutable move_count : int;
}

let empty_game_state () = {
  assertions  = Hashtbl.create (module String);
  challenged  = Hash_set.create (module String);
  move_count  = 0;
}

(** Referee adjudication of a single exchange.

    Rules (intentional logic):
    1. Proponent may not re-assert a challenged atom
    2. Opponent may challenge any asserted atom
    3. Opponent may request defense of any atom in proponent's commitments
    4. B-valued (contradictory) atoms ARE valid assertions (designated in paraconsistent logic)
*)
let referee_step state pmove opp_fn =
  state.move_count <- state.move_count + 1;
  match pmove with

  | Pass ->
      `Proponent_done

  | Withdraw atom ->
      Hashtbl.remove state.assertions atom;
      `Continue

  | Assert (atom, truth_val) ->
      (* Rule 1: cannot re-assert challenged atoms *)
      if Hash_set.mem state.challenged atom then
        `Opponent_wins
      else begin
        (* Record assertion *)
        Hashtbl.set state.assertions ~key:atom ~data:truth_val;

        (* Paraconsistent key: B assertions are VALID (no need to refuse them) *)
        let is_valid_assertion =
          match truth_val with
          | Truth tv -> is_designated tv  (* T and B are designated — acceptable *)
        in

        if not is_valid_assertion then
          (* F and N assertions are rejected immediately *)
          `Opponent_wins
        else begin
          (* Opponent responds *)
          let opp_response = opp_fn state atom truth_val in
          state.move_count <- state.move_count + 1;

          match opp_response with
          | Accept ->
              (* Opponent accepts — proponent continues *)
              `Continue

          | Challenge challenged_atom ->
              (* Opponent challenges an atom *)
              Hash_set.add state.challenged challenged_atom;
              (* Proponent must have the challenged atom in their commitments *)
              if Hashtbl.mem state.assertions challenged_atom then
                `Continue  (* proponent defends successfully *)
              else
                `Opponent_wins  (* challenged atom not in commitments *)

          | Request requested_atom ->
              (* Opponent requests justification for an atom *)
              (match Hashtbl.find state.assertions requested_atom with
               | Some _ ->
                   `Continue  (* atom is asserted; request satisfied *)
               | None ->
                   `Opponent_wins)  (* cannot produce requested justification *)
        end
      end

(** Play a full dialogical game.

    Parameters:
    - proponent: function receiving current game state, returning next move
    - opponent: function receiving state, last asserted atom and truth value, returning response
    - max_moves: terminate with Draw after this many moves (prevents infinite loops)
*)
let play
    ~(proponent : game_state -> proponent_move)
    ~(opponent  : game_state -> string -> truth_val -> opponent_response)
    ?(max_moves = 50)
    () : outcome =
  let state = empty_game_state () in
  let rec loop () =
    if state.move_count >= max_moves then
      Draw
    else begin
      let pmove = proponent state in
      match referee_step state pmove (opponent) with
      | `Continue      -> loop ()
      | `Proponent_done -> Proponent_wins
      | `Opponent_wins -> Opponent_wins
    end
  in
  loop ()

(** Query assertions from game state *)
let get_assertion state atom =
  Hashtbl.find state.assertions atom

let is_challenged state atom =
  Hash_set.mem state.challenged atom

let move_count state = state.move_count

(** Standard proponent strategy for DDG delegation decisions.

    Asserts delegation with truth value determined by oscillation state:
    - T: no oscillation — normal delegation (assert T)
    - B: oscillation detected — contradictory state (assert B — VALID in paraconsistent logic)
    - F/N: fallback — pass immediately (no valid delegation claim)

    After first assertion, Pass (proponent satisfied with having stated their position).
*)
let delegation_proponent ~atom_name ~delegation_truth =
  fun state ->
    if move_count state = 0 then
      Assert (atom_name, delegation_truth)
    else
      Pass  (* proponent already made their claim *)

(** Standard opponent strategy for DDG contradiction checking.

    - If the assertion is B (contradictory): challenge it
      (In paraconsistent logic this is allowed, but opponent can still push back)
    - If the assertion is T: accept
    - Otherwise: challenge

    Note: challenging a B assertion does NOT cause explosion.
    B is a designated value — the proponent defends by noting the contradiction is real.
*)
let oscillation_opponent ~oscillation_detected =
  fun _state atom truth_val ->
    let (Truth tv) = truth_val in
    match tv with
    | B when oscillation_detected ->
        (* Contradiction detected AND present in assertion — challenge *)
        Challenge atom
    | T ->
        (* Normal delegation — accept *)
        Accept
    | _ ->
        (* F or N asserted — should not happen (referee rejects), but challenge anyway *)
        Challenge atom

(** Run DDG delegation decision as a dialogical game.

    Returns true if delegation is decided (proponent wins with T or B),
    false if execution is decided (opponent wins or draw).
*)
let decide_delegation_dialectically
    ~atom_name
    ~delegation_truth
    ~oscillation_detected =
  let proponent = delegation_proponent ~atom_name ~delegation_truth in
  let opponent  = oscillation_opponent ~oscillation_detected in
  match play ~proponent ~opponent () with
  | Proponent_wins -> true   (* delegation proceeds *)
  | Opponent_wins  -> false  (* execute instead *)
  | Draw           -> false  (* cannot decide — default to execute *)
