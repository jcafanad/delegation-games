(** Semantic types for protocol discrimination.

    Phantom types make protocol semantics explicit at type level:
    - DIG.t is hierarchical protocol (extraction logic)
    - DEC.t is coalitional protocol (cooperation logic)
    - DDG.t is dialectical protocol (contradiction preservation)

    This prevents accidentally mixing incompatible protocols and makes
    theoretical commitments computationally legible.
*)

open Core
open Agent

(** Phantom type for hierarchical delegation (DIG) *)
type hierarchical = private Hierarchical
[@@deriving sexp_of]

(** Phantom type for coalitional delegation (DEC) *)
type coalitional = private Coalitional
[@@deriving sexp_of]

(** Phantom type for dialectical delegation (DDG) *)
type dialectical = private Dialectical
[@@deriving sexp_of]

(** Protocol semantics as GADT for future extensibility *)
type _ semantics =
  | Hierarchical : hierarchical semantics
  | Coalitional : coalitional semantics
  | Dialectical : dialectical semantics

(** Witness type for runtime semantics inspection.
    Plain variant — enables pattern matching on protocol kind at runtime.
*)
type semantics_witness =
  | Hier
  | Coal
  | Dial
[@@deriving sexp, variants]

(** Convert semantics to witness for pattern matching *)
let to_witness : type a. a semantics -> semantics_witness = function
  | Hierarchical -> Hier
  | Coalitional -> Coal
  | Dialectical -> Dial

(** Protocol signature with semantic parameter.

    Eventually protocols will be parameterized by semantics:
      type 'sem protocol = {
        semantics: 'sem semantics;
        implementation: 'sem protocol_impl;
      }

    For now, this is a preparatory interface.
*)
module type PROTOCOL_SEM = sig
  type sem
  type t

  val semantics : sem semantics
  val create : registry:Agent_registry.t -> params:string Map.M(String).t -> t
  val decide : t -> agent:Agent.t -> budget:float -> (Core_types.Action.t * t)
  val execute : t -> budget:float ->
    (Core_types.Delegation_chain.t * Core_types.Value.reward * Core_types.Equilibrium.t)
end
