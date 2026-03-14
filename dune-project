(lang dune 3.7)
(name delegation_games)
(version 0.1.0)

(generate_opam_files true)

(source (github afanador/delegation-games))
(license MIT)
(authors "Juan Afanador")
(maintainers "Juan Afanador")

(package
 (name delegation_games)
 (synopsis "Coalitional and dialectical algorithms for recursive delegation")
 (description "Implementation of DIG (hierarchical delegation via quitting games), 
DEC (coalitional delegation via Shapley/Myerson values), and DDG (dialectical 
delegation preserving contradictions). Designed for critical analysis of hierarchical 
structures and cooperative resistance under resource constraints.")
 (depends
  (ocaml (>= 4.14))
  dune
  (core (>= v0.15))
  (ppx_jane (>= v0.15))
  (owl (>= 1.1))  ; for matrix operations and statistics
  (alcotest :with-test)))
