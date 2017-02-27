(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type cache

(*type binding_id*)

(*type hashed_list = Hashed_list.Make(Binding_states).hashed_list*)

(*module Binding_idSetMap : SetMap.S with type elt = binding_id

module Binding_idMap : SetMap.Map with type elt = binding_id

module Binding_states : SetMap.S with type elt =  int * ((int, unit) Ast.link)*)


module CannonicCache : Hashed_list.Hash

module CannonicSet_and_map : SetMap.S with type elt = CannonicCache.hashed_list

module CannonicMap : SetMap.Map with type elt = CannonicCache.hashed_list

(*module PairInt  : SetMap.OrderedType with type elt = (CannonicMap.elt * int)*)

module RuleCache : Hashed_list.Hash

(*module BindingCache : Hashed_list.Hash
  with type elt = int * ((int, unit) Ast.link)*)

val init_cache: unit -> cache

val mixture_to_species_map : Ode_args.rate_convention -> cache ->
  LKappa.rule -> cache * (int * int) CannonicMap.t

val nauto: Ode_args.rate_convention -> cache ->
  LKappa.rule -> cache * int

val cannonic_form: cache -> LKappa.rule ->
  cache * RuleCache.hashed_list
