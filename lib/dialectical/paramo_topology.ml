(** Paramuno knowledge topology: encodes actual Páramo dialectical structure.

    Based on Afanador (2019) arXiv:1911.06367, four epistemic positions are modelled:

    - [Paramuno_lifeworld]:      territorial autonomy, relational ontology
    - [State_administration]:    development policy, legal frameworks
    - [Environmental_agency]:    ecosystem services (capital's delegatees)
    - [Scientific_conservation]: technocratic expertise, biodiversity science

    Attack/defense relations encode contradictions documented in Afanador (2019):
    - State argues "ecosystem services" → Paramuno attacks with autonomy claims
    - Agency argues "conservation"      → Paramuno attacks with dispossession resistance
    - Paramuno argues "territorial"     → State attacks with legality claims

    Scientific_conservation arbitrates technical/ecological claims
    (water regulation, biodiversity, ecosystem function).

    This makes the computational routing reflect the empirical reality
    documented in the Páramo ethnography rather than arbitrary list order.
*)

open Core
open Delegation_games
open Core_types
open Agent

(** Epistemic positions in Páramo territorial conflict. *)
type epistemic_position =
  | Paramuno_lifeworld
  | State_administration
  | Environmental_agency
  | Scientific_conservation
[@@deriving sexp, compare]

module Paramo_topology = struct
  type t = {
    base_topology : Agent_registry.t;
    positions     : (Agent_id.t, epistemic_position) Hashtbl.t;
  }

  let create ~base_topology =
    { base_topology; positions = Hashtbl.create (module Agent_id) }

  let assign_position t agent_id position =
    Hashtbl.set t.positions ~key:agent_id ~data:position

  let neighbors_of t agent_id =
    match Agent_registry.get t.base_topology agent_id with
    | None       -> []
    | Some agent -> Agent_registry.get_neighbors t.base_topology agent

  let position_of t agent_id = Hashtbl.find t.positions agent_id

  (** Route rejected arguments to agents with opposing epistemic positions.

      - State arguing "ecosystem" → Paramuno attackers
      - Agency arguing "conservation" → Paramuno attackers
      - Paramuno arguing "territorial" → State attackers
      - Otherwise: all neighbors (generic burden of proof)
  *)
  let get_attackers t agent_id (arg : Argument.t) =
    let neighbors = neighbors_of t agent_id in
    match position_of t agent_id with
    | Some State_administration
      when String.is_substring arg.claim ~substring:"ecosystem" ->
        List.filter neighbors ~f:(fun n ->
          match position_of t n with Some Paramuno_lifeworld -> true | _ -> false)
    | Some Environmental_agency
      when String.is_substring arg.claim ~substring:"conservation" ->
        List.filter neighbors ~f:(fun n ->
          match position_of t n with Some Paramuno_lifeworld -> true | _ -> false)
    | Some Paramuno_lifeworld
      when String.is_substring arg.claim ~substring:"territorial autonomy" ->
        List.filter neighbors ~f:(fun n ->
          match position_of t n with Some State_administration -> true | _ -> false)
    | _ -> neighbors

  (** Route to agents with aligned epistemic positions for support.

      - Paramuno defending territorial claims → other Paramuno neighbors
      - State defending development → Environmental_agency neighbors
      - Otherwise: all neighbors
  *)
  let get_defenders t agent_id (arg : Argument.t) =
    let neighbors = neighbors_of t agent_id in
    match position_of t agent_id with
    | Some Paramuno_lifeworld
      when String.is_substring arg.claim ~substring:"territorial autonomy" ->
        List.filter neighbors ~f:(fun n ->
          match position_of t n with Some Paramuno_lifeworld -> true | _ -> false)
    | Some State_administration
      when String.is_substring arg.claim ~substring:"development" ->
        List.filter neighbors ~f:(fun n ->
          match position_of t n with Some Environmental_agency -> true | _ -> false)
    | _ -> neighbors

  (** Route unknown-valuation to scientific arbiters for technical claims.

      Scientific_conservation arbitrates water, biodiversity, ecosystem claims.
      Other claims fall back to all neighbors.
  *)
  let get_arbiters t agent_id (arg : Argument.t) =
    let neighbors = neighbors_of t agent_id in
    let claim = String.lowercase arg.claim in
    (* Technical ecosystem: measurable measurement claims → route to Sci *)
    let is_technical_ecosystem =
      String.is_substring claim ~substring:"ecosystem" &&
      (String.is_substring claim ~substring:"provides" ||
       String.is_substring claim ~substring:"measurable")
    in
    let is_technical_water_biodiversity =
      String.is_substring claim ~substring:"water" ||
      String.is_substring claim ~substring:"biodiversity"
    in
    if is_technical_ecosystem || is_technical_water_biodiversity
    then
      (* Route to Scientific (measurement expertise) *)
      List.filter neighbors ~f:(fun n ->
        match position_of t n with Some Scientific_conservation -> true | _ -> false)
    else
      (* Political or generic claims: route to ALL neighbors,
         finding whoever holds political-epistemic standing (Paramuno) *)
      neighbors
end
