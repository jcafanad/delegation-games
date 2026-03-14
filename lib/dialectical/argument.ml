(** Arguments in dialogical delegation.

    Unlike tasks (binary execute/delegate), arguments are propositions
    with claims, grounds, and potential defeaters.

    In DIG/DEC, delegation passes a *task* (something to be done).
    In DDG, delegation passes an *argument* (a claim to be evaluated):
    - claim: the proposition being advanced
    - grounds: supporting reasons
    - defeaters: counterarguments that undermine the claim

    Example Páramo argument:
    - Claim: "This territory should be designated as ecosystem service provider"
    - Grounds: ["Provides water regulation for downstream communities"]
    - Defeaters: ["Paramuno communities have prior land claims",
                  "Ecosystem services framework is colonial imposition"]

    Defeaters are mutable because they accumulate as the argument
    traverses the delegation network: each agent may add new defeaters
    based on local knowledge and structural position.

    Theoretical grounding:
    The defeater accumulation models how contradictions emerge through
    engagement — not as pre-existing failures but as the relational
    outcome of argument meeting its opposition in the network.
*)

open Core
open Delegation_games
open Core_types

type t = {
  id       : string;
  claim    : string;
  grounds  : string list;
  mutable defeaters : string list;
}
[@@deriving sexp]

(** Construct an argument representing a delegation request.

    The claim asserts that the delegatee should handle the task.
    Grounds provide initial justification from the delegator's perspective.
    Defeaters start empty — they accumulate as the argument propagates.
*)
let of_delegation_request ~delegator ~delegatee =
  {
    id        = sprintf "delegate_%d_to_%d"
                  (Agent_id.to_int delegator)
                  (Agent_id.to_int delegatee);
    claim     = sprintf "Agent %d should handle this task"
                  (Agent_id.to_int delegatee);
    grounds   = [
      sprintf "Agent %d has relevant capabilities" (Agent_id.to_int delegatee);
      sprintf "Agent %d occupies appropriate structural position" (Agent_id.to_int delegatee);
    ];
    defeaters = [];
  }

(** Create argument with custom claim for testing specific scenarios. *)
let create ~id ~claim ~grounds =
  { id; claim; grounds; defeaters = [] }

(** Initial argument for the root delegation (no specific delegatee yet). *)
let root_argument () = {
  id        = "root_delegation";
  claim     = "This task should be delegated through the network";
  grounds   = [
    "Task complexity exceeds individual capacity";
    "Distributed handling reflects collective responsibility";
  ];
  defeaters = [];
}

(** Páramo-specific: argument advancing ecosystem services governance.

    This is the claim the State/Environmental_agency advances.
    Paramuno communities evaluate this as F and add autonomy defeaters.
    When enough defeaters accumulate (= grounds), B emerges.
*)
let paramo_ecosystem_argument () = {
  id        = "ecosystem_governance";
  claim     = "ecosystem services framework should govern Páramo commons";
  grounds   = [
    "Ecosystem services provide water regulation for downstream communities";
    "Carbon sequestration creates regional climate stability";
  ];
  defeaters = [];
}

(** Páramo-specific: argument advancing territorial autonomy.

    This is the claim Paramuno communities advance.
    State/Agency evaluate this as F and add legality defeaters.
*)
let paramo_territorial_argument () = {
  id        = "territorial_autonomy";
  claim     = "territorial autonomy is the legitimate basis for Páramo governance";
  grounds   = [
    "Paramuno communities have inhabited and maintained this territory for generations";
    "Prior informed consent is required under international indigenous rights law";
  ];
  defeaters = [];
}

(** Páramo-specific: argument advancing development policy.

    This is the claim the State advances in development contexts.
    Environmental_agency evaluates this as B (contradictory mandate:
    must support development AND protect conservation areas).
*)
let paramo_development_argument () = {
  id        = "development_policy";
  claim     = "development projects should proceed in Páramo zone";
  grounds   = [
    "Economic growth requires infrastructure access to highland resources";
    "National development policy mandates integration of frontier territories";
  ];
  defeaters = [];
}

(** Páramo-specific: technical ecosystem claim — measurable water regulation.

    All epistemic positions evaluate this as T: the measurement claim is
    empirically verifiable. Terminates at depth=1 regardless of root.
    Claim text triggers technical routing in paramo_topology get_arbiters.
*)
let paramo_ecosystem_technical_argument () = {
  id        = "ecosystem_technical";
  claim     = "This territory provides measurable ecosystem services including water regulation";
  grounds   = [
    "Hydrological measurement documents water flow from páramo to downstream communities";
    "Biodiversity surveys confirm 47+ endemic species in highland ecosystem";
  ];
  defeaters = [];
}

(** Páramo-specific: political ecosystem claim — services framework as extraction.

    Technical positions (Sci, Env) evaluate this as N: they lack
    political-epistemic standing to judge whether the framework constitutes
    colonial extraction. Paramuno evaluates as B: water regulation is real
    AND the services framing commodifies their territory.

    This is the core dialetheia operationalized:
    capability to measure ≠ capability to judge extraction.
*)
let paramo_ecosystem_political_argument () = {
  id        = "ecosystem_political";
  claim     = "Ecosystem services framework enables colonial extraction of Páramo territory";
  grounds   = [
    "Territorial autonomy predates conservation mandates by generations";
    "Services framing commodifies relational ontology of páramo stewardship";
  ];
  defeaters = [];
}

(** Páramo-specific: water regulation as a measurable technical claim.

    Scientific_conservation and Paramuno_lifeworld evaluate as T.
    State and Environmental_agency evaluate as N (lack technical standing).
    Routes to Sci arbiters via paramo_topology get_arbiters.
*)
let paramo_water_argument () = {
  id        = "water_regulation";
  claim     = "Water regulation from páramo provides hydrological stability downstream";
  grounds   = [
    "Hydrological models confirm páramo as primary dry-season water source";
  ];
  defeaters = [];
}

(** Páramo-specific: biodiversity conservation as a technical scientific claim.

    Scientific_conservation and Paramuno_lifeworld evaluate as T.
    State and Environmental_agency evaluate as N.
*)
let paramo_biodiversity_argument () = {
  id        = "biodiversity_conservation";
  claim     = "Biodiversity conservation requires scientific management of páramo access";
  grounds   = [
    "Endemic species require undisturbed habitat for population viability";
  ];
  defeaters = [];
}

(** Add a defeater to this argument (idempotent). *)
let add_defeater t defeater =
  if not (List.mem t.defeaters defeater ~equal:String.equal) then
    t.defeaters <- defeater :: t.defeaters

(** True if any defeaters have been registered against this argument. *)
let is_defeated t =
  not (List.is_empty t.defeaters)

(** Number of grounds minus number of defeaters.
    Positive: grounds outweigh defeaters (claim holds).
    Zero/negative: contradiction or defeat.
*)
let dialectical_strength t =
  List.length t.grounds - List.length t.defeaters

(** Serialize grounds as JSON array *)
let grounds_to_json t =
  sprintf "[%s]"
    (List.map t.grounds ~f:(fun s -> sprintf "%S" s)
     |> String.concat ~sep:", ")

(** Serialize defeaters as JSON array *)
let defeaters_to_json t =
  sprintf "[%s]"
    (List.map t.defeaters ~f:(fun s -> sprintf "%S" s)
     |> String.concat ~sep:", ")

(** Serialize argument as JSON for chuaque FFI *)
let to_json t =
  sprintf {|{"id": %S, "claim": %S, "grounds": %s, "defeaters": %s}|}
    t.id t.claim (grounds_to_json t) (defeaters_to_json t)
