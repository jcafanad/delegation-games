(** Abstract argumentation framework for evaluating arguments.

    Module-type-based design allows swapping evaluation backends:
    - Dung_framework: classical Dung-style extension semantics (no deps)
    - Chuaque_framework: delegates to Python chuaque module via FFI

    Both return Belnap_gadt.truth_val:
    - T: argument is accepted (no undefeated defeaters)
    - F: argument is rejected (defeaters dominate grounds)
    - B: argument is contradictory (grounds and defeaters in tension) ← DDG's key state
    - N: insufficient information to evaluate

    The framework interface takes no state — each call is self-contained.
    Stateful learning could be added as a separate concern.
*)

open Core
open Delegation_games
open Core_types
open Belnap_gadt
open Argument

(** Abstract interface for argumentation frameworks *)
module type FRAMEWORK = sig
  (** Evaluate an argument from a specific agent's perspective.

      Returns a Belnap truth value representing the argument's status.
      B (contradictory) is a valid, terminal evaluation — not an error.
  *)
  val evaluate :
    agent_id:Agent_id.t ->
    arg:Argument.t ->
    truth_val

  (** Find additional defeaters an agent can contribute.

      Returns a (possibly empty) list of defeater strings
      that this agent adds to the argument based on local knowledge.
  *)
  val find_defeaters :
    agent_id:Agent_id.t ->
    arg:Argument.t ->
    string list
end

(** Simple Dung-style framework — no external dependencies.

    Evaluation heuristic:
    - No defeaters → T (accepted)
    - More defeaters than grounds → F (rejected)
    - Equal counts → B (contradictory — preserved, not resolved)
    - Agent with no grounds context → N (unknown)

    Note: this is a pragmatic implementation of Dung (1995) abstract
    argumentation. A full implementation would compute stable/preferred
    extensions; this uses simple counting as a proxy.
*)
module Dung_framework : FRAMEWORK = struct
  let evaluate ~agent_id:_ ~arg =
    let n_grounds   = List.length arg.grounds in
    let n_defeaters = List.length arg.defeaters in
    if n_grounds = 0 && n_defeaters = 0 then
      Truth N   (* no information *)
    else if n_defeaters = 0 then
      Truth T   (* accepted: grounds with no opposition *)
    else if n_defeaters > n_grounds then
      Truth F   (* rejected: defeaters dominate *)
    else if n_defeaters = n_grounds then
      Truth B   (* contradictory: equal tension — PRESERVE THIS STATE *)
    else
      Truth T   (* grounds still outweigh defeaters *)

  (** Dung framework does not add external defeaters.
      Defeater discovery is an empirical matter; see Chuaque_framework.
  *)
  let find_defeaters ~agent_id:_ ~arg:_ = []
end

(** Position-based framework — simulates structural context.

    Agents at deeper positions in the hierarchy introduce defeaters
    reflecting structural contradictions (territorial proximity to
    the contradiction's source).

    Used when chuaque is unavailable but position-sensitive evaluation
    is needed.
*)
module Position_framework : FRAMEWORK = struct
  let evaluate ~agent_id ~arg =
    let id_int = Agent_id.to_int agent_id in
    let n_grounds   = List.length arg.grounds in
    let n_defeaters = List.length arg.defeaters in
    (* Deep agents (high id) are closer to structural contradiction *)
    if id_int > 5 && n_defeaters >= n_grounds then
      Truth B   (* deeper agents see more contradiction *)
    else
      Dung_framework.evaluate ~agent_id ~arg

  (** Deeper agents generate defeaters from structural position. *)
  let find_defeaters ~agent_id ~arg:_ =
    let id_int = Agent_id.to_int agent_id in
    if id_int > 3 then
      [ sprintf "Territorial claim by agent %d conflicts with delegation" id_int ]
    else
      []
end

(** chuaque-based framework — calls Python chuaque module via FFI.

    Uses Chuaque_ffi subprocess interface to evaluate arguments
    dialectically. Falls back to Dung_framework if chuaque unavailable.

    This is the full paraconsistent evaluation path:
    - chuaque implements Rescher-Manor style argument weighting
    - Returns B for genuine dialetheic conflicts
    - Finds defeaters via paraconsistent query
*)
module Chuaque_framework : FRAMEWORK = struct
  let evaluate ~agent_id:_ ~arg =
    let json_input = Argument.to_json arg in
    match Chuaque_ffi.evaluate_argument json_input with
    | Some "T" -> Truth T
    | Some "F" -> Truth F
    | Some "B" -> Truth B
    | Some "N" | None | Some _ -> Truth N

  let find_defeaters ~agent_id:_ ~arg =
    match Chuaque_ffi.query_defeaters
            ~claim:arg.claim
            ~grounds:arg.grounds with
    | Some defeaters -> defeaters
    | None -> []
end

(** Position-aware Páramo argumentation framework.

    Evaluates arguments using a position × claim_type matrix that encodes
    contradictions documented in Afanador (2019) arXiv:1911.06367:

    - Paramuno_lifeworld × Ecosystem_services   → B  (genuine dialetheia:
        accepts water regulation empirically AND rejects colonial extraction)
    - Environmental_agency × Development_policy → B  (contradictory mandate:
        agency must promote "sustainable development" AND protect ecosystems)
    - State × Territorial_autonomy              → F  (legality objection)
    - Paramuno × Territorial_autonomy           → T  (own framing)
    - Scientific × Water_regulation             → T  (technical competence)
    - Unknown position                          → N  (no epistemic standing)

    Unlike the accumulation approach (which derives B by counting defeaters),
    B here is directly encoded — a genuine dialetheia, not a logical error.

    Usage:
    {[
      let module PF = Make_paramo_framework(struct
        let position_of id = Paramo_topology.Paramo_topology.position_of topo id
      end) in
      module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF)
    ]}
*)
module Make_paramo_framework
    (Ctx : sig
       val position_of : Agent_id.t -> Paramo_topology.epistemic_position option
     end)
: FRAMEWORK = struct

  open Paramo_topology

  (** Claim types recognised in Páramo territorial conflict. *)
  type claim_type =
    | Territorial_autonomy         (** Paramuno territorial rights *)
    | Ecosystem_services_technical (** Measurable water/biodiversity regulation *)
    | Ecosystem_services_political (** Services framework as colonial extraction *)
    | Development_policy           (** State development projects *)
    | Water_regulation             (** Technical/scientific hydrology *)
    | Biodiversity_conservation    (** Scientific conservation *)
    | Unknown_claim                (** Unrecognised pattern *)

  (** Classify claim content into a structural type.

      Ecosystem claims are split on epistemic grounds:
      - Technical: "provides"/"measurable" keywords → measurement claim
      - Political: framework critique → requires political-epistemic standpoint *)
  let classify_claim (arg : Argument.t) : claim_type =
    let c = String.lowercase arg.claim in
    if String.is_substring c ~substring:"territorial"
    || String.is_substring c ~substring:"autonomy"
    || String.is_substring c ~substring:"land rights"
    then Territorial_autonomy
    else if String.is_substring c ~substring:"ecosystem service"
    then
      if String.is_substring c ~substring:"provides"
      || String.is_substring c ~substring:"measurable"
      then Ecosystem_services_technical
      else Ecosystem_services_political
    else if String.is_substring c ~substring:"environmental service"
    then Ecosystem_services_political
    else if String.is_substring c ~substring:"development"
         || String.is_substring c ~substring:"economic growth"
    then Development_policy
    else if String.is_substring c ~substring:"water regulation"
         || String.is_substring c ~substring:"hydrological"
    then Water_regulation
    else if String.is_substring c ~substring:"biodiversity"
         || String.is_substring c ~substring:"conservation"
    then Biodiversity_conservation
    else Unknown_claim

  (** Position × claim_type evaluation matrix.

      Directly encodes structural contradictions (B) rather than deriving
      them from defeater accumulation, making the dialetheia explicit. *)
  let evaluate_positioned position (arg : Argument.t) =
    match (position, classify_claim arg) with

    (* --- Territorial autonomy claims --- *)
    | Paramuno_lifeworld,    Territorial_autonomy -> Truth T
    | State_administration,  Territorial_autonomy -> Truth F
    | Environmental_agency,  Territorial_autonomy -> Truth F
    | Scientific_conservation, Territorial_autonomy -> Truth N

    (* --- Ecosystem services: technical claims (measurable) --- *)
    | Paramuno_lifeworld,      Ecosystem_services_technical -> Truth T
    | State_administration,    Ecosystem_services_technical -> Truth T
    | Environmental_agency,    Ecosystem_services_technical -> Truth T
    | Scientific_conservation, Ecosystem_services_technical -> Truth T

    (* --- Ecosystem services: political claims (framework critique) --- *)
    | Paramuno_lifeworld, Ecosystem_services_political ->
        (* Genuine dialetheia: water regulation is empirically real (T) AND
           "ecosystem services" framing commodifies Paramuno territory (F).
           The contradiction is at framework level, not measurement level. *)
        Truth B
    | State_administration,    Ecosystem_services_political -> Truth T
    | Environmental_agency,    Ecosystem_services_political -> Truth N
    | Scientific_conservation, Ecosystem_services_political -> Truth N

    (* --- Development policy claims --- *)
    | State_administration,  Development_policy -> Truth T
    | Paramuno_lifeworld,    Development_policy -> Truth F
    | Environmental_agency,  Development_policy ->
        (* Contradictory institutional mandate: agencies must support
           "sustainable development" (T) while protecting conservation
           areas (F). Another irreducible dialetheia. *)
        Truth B
    | Scientific_conservation, Development_policy -> Truth N

    (* --- Technical/scientific claims --- *)
    | Scientific_conservation, Water_regulation          -> Truth T
    | Scientific_conservation, Biodiversity_conservation -> Truth T
    | Paramuno_lifeworld,      Water_regulation          -> Truth T
    | Paramuno_lifeworld,      Biodiversity_conservation -> Truth T
    | State_administration,    Water_regulation          -> Truth N
    | State_administration,    Biodiversity_conservation -> Truth N
    | Environmental_agency,    Water_regulation          -> Truth N
    | Environmental_agency,    Biodiversity_conservation -> Truth N

    (* --- Unknown claims --- *)
    | _, Unknown_claim -> Truth N

  let evaluate ~agent_id ~(arg : Argument.t) =
    match Ctx.position_of agent_id with
    | Some position -> evaluate_positioned position arg
    | None          -> Truth N   (* no epistemic standing *)

  let find_defeaters ~agent_id ~(arg : Argument.t) =
    match Ctx.position_of agent_id with

    | Some Paramuno_lifeworld ->
        (match classify_claim arg with
         | Ecosystem_services_technical -> []
         | Ecosystem_services_political ->
             [ "Ecosystem services framework commodifies Paramuno territorial \
                sovereignty without prior informed consent";
               "Conservation policy enacts dispossession under ecological legitimacy";
               "Services framing commodifies relational territory" ]
         | Development_policy ->
             [ "Development projects violate territorial rights without free, \
                prior, and informed consent";
               "Scalar economic growth erases relational ontology of páramo stewardship" ]
         | _ -> [])

    | Some State_administration ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Territorial claims lack legal standing under national constitutional framework";
               "State sovereignty supersedes unilateral local autonomy assertions" ]
         | _ -> [])

    | Some Environmental_agency ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Unregulated territorial claims threaten ecosystem service provision";
               "Conservation areas require access restrictions incompatible with open tenure" ]
         | _ -> [])

    | Some Scientific_conservation ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Biodiversity conservation requires technically managed access protocols" ]
         | _ -> [])

    | None -> []

end

(** Position-aware Páramo argumentation framework — typed-topology variant.

    Architectural improvement over [Make_paramo_framework]:
    - [Make_paramo_framework] captures position lookup as a bare closure,
      hiding the topology type.
    - [Paramo_framework] makes the topology type explicit in the functor
      signature: callers must name the type [t] and supply both the value
      [topology] and the accessor [get_position].  This makes the dependency
      on the topology representation visible at the call site and decouples
      the framework from any particular topology implementation.

    Usage:
    {[
      let module PF = Paramo_framework(struct
        type t = Paramo_topology.Paramo_topology.t
        let topology = ptopo
        let get_position = Paramo_topology.Paramo_topology.position_of
      end) in
      let module DDG = Protocol_ddg.Make_DDG(Paramo_topology.Paramo_topology)(PF) in
      ...
    ]}
*)
module Paramo_framework
    (Topo : sig
       type t
       val topology     : t
       val get_position : t -> Agent_id.t -> Paramo_topology.epistemic_position option
     end)
: FRAMEWORK = struct

  open Paramo_topology

  type claim_type =
    | Territorial_autonomy
    | Ecosystem_services_technical
    | Ecosystem_services_political
    | Development_policy
    | Water_regulation
    | Biodiversity_conservation
    | Unknown_claim

  let classify_claim (arg : Argument.t) : claim_type =
    let c = String.lowercase arg.claim in
    if String.is_substring c ~substring:"territorial"
    || String.is_substring c ~substring:"autonomy"
    || String.is_substring c ~substring:"land rights"
    then Territorial_autonomy
    else if String.is_substring c ~substring:"ecosystem service"
    then
      if String.is_substring c ~substring:"provides"
      || String.is_substring c ~substring:"measurable"
      then Ecosystem_services_technical
      else Ecosystem_services_political
    else if String.is_substring c ~substring:"environmental service"
    then Ecosystem_services_political
    else if String.is_substring c ~substring:"development"
         || String.is_substring c ~substring:"economic growth"
    then Development_policy
    else if String.is_substring c ~substring:"water regulation"
         || String.is_substring c ~substring:"hydrological"
    then Water_regulation
    else if String.is_substring c ~substring:"biodiversity"
         || String.is_substring c ~substring:"conservation"
    then Biodiversity_conservation
    else Unknown_claim

  let evaluate_positioned position (arg : Argument.t) =
    match (position, classify_claim arg) with
    | Paramuno_lifeworld,      Territorial_autonomy           -> Truth T
    | State_administration,    Territorial_autonomy           -> Truth F
    | Environmental_agency,    Territorial_autonomy           -> Truth F
    | Scientific_conservation, Territorial_autonomy           -> Truth N
    | Paramuno_lifeworld,      Ecosystem_services_technical   -> Truth T
    | State_administration,    Ecosystem_services_technical   -> Truth T
    | Environmental_agency,    Ecosystem_services_technical   -> Truth T
    | Scientific_conservation, Ecosystem_services_technical   -> Truth T
    | Paramuno_lifeworld,      Ecosystem_services_political   -> Truth B
    | State_administration,    Ecosystem_services_political   -> Truth T
    | Environmental_agency,    Ecosystem_services_political   -> Truth N
    | Scientific_conservation, Ecosystem_services_political   -> Truth N
    | State_administration,    Development_policy             -> Truth T
    | Paramuno_lifeworld,      Development_policy             -> Truth F
    | Environmental_agency,    Development_policy             -> Truth B
    | Scientific_conservation, Development_policy             -> Truth N
    | Scientific_conservation, Water_regulation               -> Truth T
    | Scientific_conservation, Biodiversity_conservation      -> Truth T
    | Paramuno_lifeworld,      Water_regulation               -> Truth T
    | Paramuno_lifeworld,      Biodiversity_conservation      -> Truth T
    | State_administration,    Water_regulation               -> Truth N
    | State_administration,    Biodiversity_conservation      -> Truth N
    | Environmental_agency,    Water_regulation               -> Truth N
    | Environmental_agency,    Biodiversity_conservation      -> Truth N
    | _,                       Unknown_claim                  -> Truth N

  let evaluate ~agent_id ~(arg : Argument.t) =
    match Topo.get_position Topo.topology agent_id with
    | Some position -> evaluate_positioned position arg
    | None          -> Truth N

  let find_defeaters ~agent_id ~(arg : Argument.t) =
    match Topo.get_position Topo.topology agent_id with

    | Some Paramuno_lifeworld ->
        (match classify_claim arg with
         | Ecosystem_services_technical -> []
         | Ecosystem_services_political ->
             [ "Ecosystem services framework commodifies Paramuno territorial \
                sovereignty without prior informed consent";
               "Conservation policy enacts dispossession under ecological legitimacy";
               "Services framing commodifies relational territory" ]
         | Development_policy ->
             [ "Development projects violate territorial rights without free, \
                prior, and informed consent";
               "Scalar economic growth erases relational ontology of páramo stewardship" ]
         | _ -> [])

    | Some State_administration ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Territorial claims lack legal standing under national constitutional framework";
               "State sovereignty supersedes unilateral local autonomy assertions" ]
         | _ -> [])

    | Some Environmental_agency ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Unregulated territorial claims threaten ecosystem service provision";
               "Conservation areas require access restrictions incompatible with open tenure" ]
         | _ -> [])

    | Some Scientific_conservation ->
        (match classify_claim arg with
         | Territorial_autonomy ->
             [ "Biodiversity conservation requires technically managed access protocols" ]
         | _ -> [])

    | None -> []

end

(** Select framework based on chuaque availability.

    At module initialization, checks if chuaque is reachable.
    Returns Chuaque_framework if available, Position_framework otherwise.
    Callers can also override by selecting a module directly.
*)
let default_framework () : (module FRAMEWORK) =
  if Chuaque_ffi.is_available () then
    (module Chuaque_framework : FRAMEWORK)
  else
    (module Position_framework : FRAMEWORK)
