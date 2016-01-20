type jf_data =
  Compression_main.secret_log_info * Compression_main.secret_step list

type t = {
  roots_of_ccs: Mods.IntSet.t Connected_component.Map.t;
  unary_candidates: Mods.Int2Set.t Mods.IntMap.t;
  unary_pathes: (int * Edges.path) Mods.Int2Map.t;
  edges: Edges.t;
  tokens: Nbr.t array;
  outdated_elements:
    Operator.DepSet.t *
    (Edges.agent * ((Connected_component.Set.t *int) * Edges.path) list) list * bool;
  story_machinery :
    ((Causal.event_kind * Connected_component.t array *
	Instantiation.abstract Instantiation.test list) list
       Connected_component.Map.t (*currently tracked ccs *)
     * jf_data) option;
}

type result = Clash | Success of t | Corrected of t

let empty ~has_tracking env = {
    roots_of_ccs = Connected_component.Map.empty;
    unary_candidates = Mods.IntMap.empty;
    unary_pathes = Mods.Int2Map.empty;
    edges = Edges.empty;
    tokens = Array.make (Environment.nb_tokens env) Nbr.zero;
    outdated_elements = Operator.DepSet.empty,[],true;
    story_machinery =
      if has_tracking
      then Some (Connected_component.Map.empty,
		 (Compression_main.init_secret_log_info (), []))
      else None;
}

let print_injections ?sigs pr f roots_of_ccs =
  Format.fprintf
    f "@[<v>%a@]"
    (Pp.set Connected_component.Map.bindings Pp.space
	    (fun f (cc,roots) ->
	     Format.fprintf
	       f "@[# @[%a@] ==>@ @[%a@]@]"
	       (Connected_component.print ?sigs true) cc
	       (Pp.set Mods.IntSet.elements Pp.comma pr) roots
	    )
    ) roots_of_ccs

let update_roots is_add map cc root =
  let va =
    Connected_component.Map.find_default Mods.IntSet.empty cc map in
  Connected_component.Map.add
    cc ((if is_add then Mods.IntSet.add else Mods.IntSet.remove) root va) map

let remove_path (x,y) pathes =
  let pair = (min x y, max x y) in
  match Mods.Int2Map.find_option pair pathes with
   | None -> pathes
   | Some (1,_) -> Mods.Int2Map.remove pair pathes
   | Some (i,p) -> Mods.Int2Map.add pair (pred i,p) pathes
let add_candidate cands pathes rule_id x y p =
  let a = min x y in
  let b = max x y in
  let va = Mods.IntMap.find_default Mods.Int2Set.empty rule_id cands in
  (Mods.IntMap.add rule_id (Mods.Int2Set.add (x,y) va) cands,
   match Mods.Int2Map.find_option (a,b) pathes with
   | None -> Mods.Int2Map.add (a,b) (1,p) pathes
   | Some (i,_) -> Mods.Int2Map.add (a,b) (succ i,p) pathes)
let remove_candidate cands pathes rule_id pair =
  let va =
    Mods.Int2Set.remove
      pair (Mods.IntMap.find_default Mods.Int2Set.empty rule_id cands) in
  ((if Mods.Int2Set.is_empty va then Mods.IntMap.remove rule_id cands
    else Mods.IntMap.add rule_id va cands), remove_path pair pathes)

let from_place (inj_nodes,inj_fresh) = function
  | Agent_place.Existing (n,id) ->
     (Connected_component.Matching.get (n,id) inj_nodes,
     Connected_component.ContentAgent.get_sort n)
  | Agent_place.Fresh (ty,id) ->
     match Mods.IntMap.find_option id inj_fresh with
     | Some x -> (x,ty)
     | None -> failwith "Rule_interpreter.from_place"

let new_place free_id (inj_nodes,inj_fresh) = function
  | Agent_place.Existing _ -> failwith "Rule_interpreter.new_place"
  | Agent_place.Fresh (_,id) ->
     (inj_nodes,Mods.IntMap.add id free_id inj_fresh)

let all_injections ?excp edges roots cca =
  snd @@
  Tools.array_fold_lefti
    (fun id (excp,inj_list) cc ->
     let cands,excp' =
       match excp with
       | Some (cc',root)
           when Connected_component.is_equal_canonicals cc cc' ->
         Mods.IntSet.add root Mods.IntSet.empty,None
       | (Some _ | None) ->
         Connected_component.Map.find_default Mods.IntSet.empty cc roots,excp in
     (excp',
      Mods.IntSet.fold
       (fun root new_injs ->
        List.fold_left
          (fun corrects inj ->
           match Connected_component.Matching.reconstruct
                   edges inj id cc root with
           | None -> corrects
           | Some new_inj -> new_inj :: corrects)
          new_injs inj_list)
       cands []))
    (excp,[Connected_component.Matching.empty]) cca

let apply_negative_transformation domain inj2graph side_effects edges = function
  | Primitives.Transformation.Agent n ->
     let nc = from_place inj2graph n in (*(A,23)*)
     let new_obs =
       Connected_component.Matching.observables_from_agent domain edges nc in
     (*this hack should disappear when chekcing O\H only*)
     let edges' =
       Edges.remove_agent nc edges in
     (side_effects,edges',new_obs)
  | Primitives.Transformation.Freed (n,s) -> (*(n,s)-bottom*)
     let (id,_ as nc) = from_place inj2graph n in (*(A,23)*)
     let new_obs =
       Connected_component.Matching.observables_from_free domain edges nc s in
     (*this hack should disappear when chekcing O\H only*)
     let edges' = Edges.remove_free id s edges in
     (side_effects,edges',new_obs)
  | Primitives.Transformation.Linked ((n,s),(n',s')) ->
     let (id,_ as nc) = from_place inj2graph n in
     let (id',_ as nc') = from_place inj2graph n' in
     let new_obs =
       Connected_component.Matching.observables_from_link
	 domain edges nc s nc' s' in
     let edges' = Edges.remove_link id s id' s' edges in
     (side_effects,edges',new_obs)
  | Primitives.Transformation.NegativeWhatEver (n,s) ->
     let (id,_ as nc) = from_place inj2graph n in
     begin
       match Edges.link_destination id s edges with
       | None ->
	  let new_obs = Connected_component.Matching.observables_from_free
			  domain edges nc s in
	  (side_effects,Edges.remove_free id s edges,new_obs)
       | Some ((id',_ as nc'),s') ->
	  let new_obs = Connected_component.Matching.observables_from_link
			  domain edges nc s nc' s' in
	  ((nc',s')::side_effects,Edges.remove_link id s id' s' edges, new_obs)
     end
  | Primitives.Transformation.PositiveInternalized _ ->
     raise
       (ExceptionDefn.Internal_Error
	  (Location.dummy_annot "PositiveInternalized in negative update"))
  | Primitives.Transformation.NegativeInternalized (n,s) ->
     let (id,_ as nc) = from_place inj2graph n in
     let i  = Edges.get_internal id s edges in
     let new_obs =
       Connected_component.Matching.observables_from_internal
	 domain edges nc s i in
     let edges' = Edges.remove_internal id s edges in
     (side_effects,edges',new_obs)

let apply_positive_transformation
      sigs domain inj2graph side_effects edges = function
  | Primitives.Transformation.Agent n ->
     let nc, inj2graph',edges' =
       let ty = Agent_place.get_type n in
       let id,edges' = Edges.add_agent sigs ty edges in
       (id,ty),new_place id inj2graph n,edges' in
     let new_obs =
       Connected_component.Matching.observables_from_agent domain edges' nc in
     (*this hack should disappear when chekcing O\H only*)
     (inj2graph',side_effects,edges',new_obs)
  | Primitives.Transformation.Freed (n,s) -> (*(n,s)-bottom*)
     let (id,_ as nc) = from_place inj2graph n in (*(A,23)*)
     let edges' = Edges.add_free id s edges in
     let new_obs =
       Connected_component.Matching.observables_from_free domain edges' nc s in
     (*this hack should disappear when chekcing O\H only*)
     let side_effects' =
       Tools.list_smart_filter (fun x -> x <> (nc,s)) side_effects in
     (inj2graph,side_effects',edges',new_obs)
  | Primitives.Transformation.Linked ((n,s),(n',s')) ->
     let nc = from_place inj2graph n in
     let nc' = from_place inj2graph n' in
     let edges' = Edges.add_link nc s nc' s' edges in
     let new_obs =
       Connected_component.Matching.observables_from_link
	 domain edges' nc s nc' s' in
     let side_effects' = Tools.list_smart_filter
			   (fun x -> x<>(nc,s) && x<>(nc',s')) side_effects in
     (inj2graph,side_effects',edges',new_obs)
  | Primitives.Transformation.NegativeWhatEver _ ->
     raise
       (ExceptionDefn.Internal_Error
	  (Location.dummy_annot "NegativeWhatEver in positive update"))
  | Primitives.Transformation.PositiveInternalized (n,s,i) ->
     let (id,_ as nc) = from_place inj2graph n in
     let edges' = Edges.add_internal id s i edges in
     let new_obs =
       Connected_component.Matching.observables_from_internal
	 domain edges' nc s i in
     (inj2graph,side_effects,edges',new_obs)
  | Primitives.Transformation.NegativeInternalized _ ->
     raise
       (ExceptionDefn.Internal_Error
	  (Location.dummy_annot "NegativeInternalized in positive update"))

let deal_transformation is_add sigs domain to_explore_unaries
			inj2graph side_effects edges roots transf =
  (*transf: abstract edge to be added or removed*)
  let inj,sides,graph,(obs,deps) =
    (*inj: inj2graph', graph: edges', obs: delta_roots*)
    if is_add then apply_positive_transformation
		     sigs domain inj2graph side_effects edges transf
    else
      let a,b,c = apply_negative_transformation
		    domain inj2graph side_effects edges transf in
      (inj2graph,a,b,c) in
  let roots' =
    List.fold_left
      (fun r' (cc,(root,_)) ->
       (* let () = *)
       (* 	 Format.eprintf *)
       (* 	   "@[add:%b %a in %i@]@." is_add *)
       (* 	   (Connected_component.print true ~sigs:!Debug.global_sigs) cc root in *)
       update_roots is_add r' cc root) roots obs in
  let to_explore' =
    if not is_add then to_explore_unaries
    else
      match transf with
      | (Primitives.Transformation.Freed _ |
	 Primitives.Transformation.Agent _ |
	 Primitives.Transformation.PositiveInternalized _) -> to_explore_unaries
      | (Primitives.Transformation.NegativeWhatEver _ |
	 Primitives.Transformation.NegativeInternalized _) -> assert false
      | Primitives.Transformation.Linked ((n,_),(n',_)) ->
	 if Agent_place.same_connected_component n n'
	 then to_explore_unaries
	 else
	   let nc = from_place inj n in
	   nc::to_explore_unaries in
  ((inj,sides,graph,to_explore',roots',deps),obs)

let deal_remaining_side_effect domain edges roots ((id,_ as nc),s) =
  let graph = Edges.add_free id s edges in
  let obs,deps =
    Connected_component.Matching.observables_from_free domain graph nc s in
  let roots' =
    List.fold_left
      (fun r' (cc,(root,_)) -> update_roots true r' cc root) roots obs in
  ((graph,roots',deps),obs)

let add_path_to_tests path tests =
  let path_agents,path_tests =
    List.fold_left
      (fun (ag,te) (((id,_ as a),_),((id',_ as a'),_)) ->
       let ag',te' =
	 if Mods.IntSet.mem id ag then ag,te
	 else Mods.IntSet.add id ag,Instantiation.Is_Here a::te in
       if Mods.IntSet.mem id' ag' then ag',te'
       else Mods.IntSet.add id' ag',Instantiation.Is_Here a'::te')
      (Mods.IntSet.empty,[]) path in
  let tests' =
    List.filter (function
		  | Instantiation.Is_Here (id, _) ->
		     not @@ Mods.IntSet.mem id path_agents
		  | Instantiation.Is_Bound_to (a,b) ->
		     List.for_all (fun (x,y) -> x <> a && x <> b && y<>a && y<>b) path
		  | (Instantiation.Has_Internal _ | Instantiation.Is_Free _
		     | Instantiation.Is_Bound _
		     | Instantiation.Has_Binding_type _) -> true)
		tests in
  List.rev_append
    path_tests
    (Tools.list_rev_map_append
       (fun (x,y) -> Instantiation.Is_Bound_to (x,y)) path tests')

let store_event counter inj2graph new_tracked_obs_instances event_kind
		?path extra_side_effects rule = function
  | None as x -> x
  | Some (x,(info,steps)) ->
     let (ctests,(ctransfs,cside_sites,csides)) =
       Instantiation.concretize_event
	 (fun p -> let (x,_) = from_place inj2graph p in x)
	 rule.Primitives.instantiations in
     let cactions =
       (ctransfs,cside_sites,List.rev_append extra_side_effects csides) in
     let full_concrete_event =
       match path with
       | None -> ctests,cactions
       | Some path ->
	  add_path_to_tests path ctests,cactions in
     let infos',steps' =
       Compression_main.secret_store_event
	 info (event_kind,full_concrete_event) steps in
     let infos'',steps'' =
       List.fold_left
	 (fun (infos,steps) (ev,obs_tests) ->
	  let obs =
	    (ev,
	     obs_tests,
	    Counter.next_story counter) in
	  Compression_main.secret_store_obs infos obs steps)
	 (infos',steps')
	 new_tracked_obs_instances
     in
       Some (x,(infos'',steps''))

let store_obs edges roots obs acc = function
  | None -> acc
  | Some (tracked,_) ->
     List.fold_left
       (fun acc (cc,(root,_)) ->
	try
	  List.fold_left
	    (fun acc (ev,ccs,tests) ->
	     List.fold_left
	       (fun acc inj ->
		let tests' =
		  List.map (Instantiation.concretize_test
			      (fun p ->
			       let (x,_) =
				 from_place (inj,Mods.IntMap.empty) p in x))
			   tests in
		(ev,tests') :: acc)
	       acc (all_injections ~excp:(cc,root) edges roots ccs))
	    acc (Connected_component.Map.find_default [] cc tracked)
	with Not_found -> acc)
       acc obs

let exists_root_of_unary_ccs unary_ccs roots =
  not @@
    Connected_component.Set.for_all
      (fun cc ->
       Mods.IntSet.is_empty
	 (Connected_component.Map.find_default Mods.IntSet.empty cc roots))
      unary_ccs

let potential_root_of_unary_ccs unary_ccs roots i =
  let ccs =
    Connected_component.Set.filter
      (fun cc ->
	Mods.IntSet.mem
	  i (Connected_component.Map.find_default Mods.IntSet.empty cc roots))
      unary_ccs in
  if Connected_component.Set.is_empty ccs then None else Some ccs

let remove_unary_instances unaries obs deps =
  Operator.DepSet.fold
    (fun x (cands,pathes as acc) ->
     match x with
     | (Operator.ALG _ | Operator.PERT _) -> acc
     | Operator.RULE i ->
	match Mods.IntMap.find_option i cands with
	| None -> acc
	| Some l ->
	   let byebye,stay =
	     Mods.Int2Set.partition
	       (fun (x,y) -> List.exists (fun (_,(a,_)) -> a = x || a = y) obs)
	       l in
	   ((if Mods.Int2Set.is_empty stay then Mods.IntMap.remove i cands
	     else Mods.IntMap.add i stay cands),
	    Mods.Int2Set.fold remove_path byebye pathes)
    ) deps unaries

let update_edges
      sigs counter domain unary_ccs inj_nodes state event_kind ?path rule =
  let former_deps,unary_cands,no_unary = state.outdated_elements in
  (*Negative update*)
  let aux,side_effects,(unary_candidates',unary_pathes') =
    List.fold_left
      (fun ((inj2graph,edges,roots,(deps,unaries_to_expl)),sides,unaries)
	   transf ->
       (*inj2graph: abs -> conc, roots define the injection that is used*)
       let ((a,sides',b,_,c,new_deps),new_obs) =
	 deal_transformation
	   false sigs domain unaries_to_expl inj2graph sides edges roots transf in
       ((a,b,c,(Operator.DepSet.union new_deps deps,unaries_to_expl)),
	sides',remove_unary_instances unaries new_obs new_deps))
      (((inj_nodes,Mods.IntMap.empty), (*initial inj2graph: (existing,new) *)
	state.edges,state.roots_of_ccs,(former_deps,[])),
       [],
       (state.unary_candidates,state.unary_pathes))
      rule.Primitives.removed (*removed: statically defined edges*)
  in
  let ((final_inj2graph,edges',roots',(rev_deps',unaries_to_explore)),
       remaining_side_effects,new_tracked_obs_instances,all_new_obs) =
    List.fold_left
      (fun ((inj2graph,edges,roots,(deps,unaries_to_expl)),
	    sides,tracked_inst,all_nobs) transf ->
       let (a,sides',b,unaries_to_expl',c,new_deps),new_obs =
	 deal_transformation
	   true sigs domain unaries_to_expl inj2graph sides edges roots transf in
       ((a,b,c,(Operator.DepSet.union deps new_deps,unaries_to_expl')),sides',
	store_obs b c new_obs tracked_inst state.story_machinery,
	match new_obs with [] -> all_nobs | l -> l::all_nobs))
      (aux,side_effects,[],[])
      rule.Primitives.inserted (*statically defined edges*) in
  let (edges'',roots'',rev_deps'',new_tracked_obs_instances',all_new_obs') =
    List.fold_left
      (fun (edges,roots,deps,tracked_inst,all_nobs) side ->
       let (b,c,new_deps),new_obs =
	 deal_remaining_side_effect domain edges roots side in
       (b,c,Operator.DepSet.union deps new_deps,
	store_obs b c new_obs tracked_inst state.story_machinery,
	match new_obs with [] -> all_nobs | l -> l::all_nobs))
      (edges',roots',rev_deps',new_tracked_obs_instances,all_new_obs)
      remaining_side_effects in
  let unary_cands',no_unary' =
    if Connected_component.Set.is_empty unary_ccs
    then (unary_cands,no_unary)
    else
      let unary_pack =
	List.fold_left
	  (List.fold_left
	     (fun (unary_cands,_ as acc) (cc,root) ->
	      if Connected_component.Set.mem cc unary_ccs then
		(root,[(Connected_component.Set.singleton cc,fst root),
		       Edges.empty_path])::unary_cands,false
	      else acc)) (unary_cands,no_unary) all_new_obs' in
      if exists_root_of_unary_ccs unary_ccs roots''
      then
	List.fold_left
	  (fun (unary_cands,_ as acc) (id,ty) ->
	   match
	     Edges.pathes_of_interrest
	       (potential_root_of_unary_ccs unary_ccs roots')
	       sigs edges'' ty id Edges.empty_path with
	   | [] -> acc
	   | l -> ((id,ty),l) :: unary_cands,false) unary_pack unaries_to_explore
      else unary_pack in
  (*Store event*)
  let story_machinery' =
    store_event
      counter final_inj2graph new_tracked_obs_instances' event_kind
      ?path remaining_side_effects rule state.story_machinery in

  { roots_of_ccs = roots''; unary_candidates = unary_candidates';
    unary_pathes = unary_pathes'; edges = edges''; tokens = state.tokens;
    outdated_elements = (rev_deps'',unary_cands',no_unary');
    story_machinery = story_machinery'; }

let raw_instance_number state ccs_l =
  let size cc =
    Mods.IntSet.size (Connected_component.Map.find_default
			Mods.IntSet.empty cc state.roots_of_ccs) in
  let rect_approx ccs =
    Array.fold_left (fun acc cc ->  acc * (size cc)) 1 ccs in
  List.fold_left (fun acc ccs -> acc + (rect_approx ccs)) 0 ccs_l
let instance_number state ccs_l =
  Nbr.I (raw_instance_number state ccs_l)

let value_bool ~get_alg counter state expr =
  Expr_interpreter.value_bool
    counter ~get_alg
    ~get_mix:(fun ccs -> instance_number state ccs)
    ~get_tok:(fun i -> state.tokens.(i))
    expr
let value_alg ~get_alg counter state alg =
  Expr_interpreter.value_alg
    counter ~get_alg
    ~get_mix:(fun ccs -> instance_number state ccs)
    ~get_tok:(fun i -> state.tokens.(i))
    alg

let extra_outdated_var i state =
  let deps,unary_cands,no_unary = state.outdated_elements in
  {state with outdated_elements =
		(Operator.DepSet.add (Operator.ALG i) deps,unary_cands,no_unary)}

let new_unary_instances sigs rule_id cc1 cc2 created_obs state =
  let (unary_candidates,unary_pathes) =
    List.fold_left
      (fun acc ((restart,restart_ty),l) ->
       List.fold_left
	 (fun acc ((ccs,id),path) ->
	  let path = Edges.rev_path path in
	  Connected_component.Set.fold
	    (fun cc acc ->
	     try
	       let goals,reverse =
		 if Connected_component.is_equal_canonicals cc cc1
		 then
		   match Connected_component.Map.find_option
		     cc2 state.roots_of_ccs with
		   | Some x -> x,false
		   | None -> raise Not_found
		 else if Connected_component.is_equal_canonicals cc cc2
		 then
		   match Connected_component.Map.find_option
		     cc1 state.roots_of_ccs with
		   | Some x -> x,true
		   | None -> raise Not_found
		 else raise Not_found in
	       List.fold_left
		 (fun (cands,pathes) (((),d),p) ->
		  if reverse
		  then add_candidate cands pathes rule_id d id p
		  else add_candidate cands pathes rule_id id d p)
		 acc
		 (Edges.pathes_of_interrest
		    (fun x -> if Mods.IntSet.mem x goals then Some () else None)
		    sigs state.edges restart_ty restart path)
	     with Not_found -> acc)
	    ccs acc) acc l)
      (state.unary_candidates,state.unary_pathes) created_obs in
  {state with unary_candidates = unary_candidates;
	      unary_pathes = unary_pathes }

let update_outdated_activities ~get_alg store env counter state =
  let deps,unary_cands,no_unary = state.outdated_elements in
  let store_activity id syntax_id rate cc_va =
    let rate =
      Nbr.to_float @@ value_alg counter state ~get_alg rate in
    let () =
      if !Parameter.debugModeOn then
	Format.printf "@[%sule %a has now %i instances.@]@."
		      (if id mod 2 = 1 then "Unary r" else "R")
		      (Environment.print_rule ~env) (id/2) cc_va in
    let act =
      if cc_va = 0 then 0. else rate *. float_of_int cc_va in
    store id syntax_id act in
  let rec aux deps =
    Operator.DepSet.iter
      (fun dep ->
       match dep with
	| Operator.ALG j ->
	   aux (Environment.get_alg_reverse_dependencies env j)
	| Operator.PERT (-1) -> () (* TODO *)
	| Operator.PERT _ -> assert false
	| Operator.RULE i ->
	   let rule = Environment.get_rule env i in
	   let cc_va =
	     if rule.Primitives.rate_absolute then 1
	     else
	       raw_instance_number
		 state [rule.Primitives.connected_components] in
	   store_activity (2*i) rule.Primitives.syntactic_rule
			  rule.Primitives.rate cc_va) deps in
  let () = aux (Environment.get_always_outdated env) in
  let () = aux deps in
  let state' =
    if no_unary then state else
      Environment.fold_rules
	(fun i state rule ->
	 match rule.Primitives.unary_rate with
	 | None -> state
	 | Some unrate ->
	    let state' =
	      new_unary_instances
		(Environment.signatures env)
		i rule.Primitives.connected_components.(0)
		rule.Primitives.connected_components.(1) unary_cands state in
	    let va =
	      Mods.Int2Set.size
		(Mods.IntMap.find_default Mods.Int2Set.empty i state'.unary_candidates) in
	    let () =
	      store_activity (2*i+1) rule.Primitives.syntactic_rule unrate va in
	    state') state env in
  {state' with outdated_elements = (Operator.DepSet.empty,[],true) }

let update_tokens ~get_alg env counter state consumed injected =
  let do_op op state l =
    List.fold_left
      (fun st (expr,i) ->
	let () =
	  st.tokens.(i) <-
	    op st.tokens.(i) (value_alg ~get_alg counter st expr) in
	let deps' = Environment.get_token_reverse_dependencies env i in
	if Operator.DepSet.is_empty deps' then st
	else
	  let deps,unary_cands,no_unary = st.outdated_elements in
	  { st with outdated_elements =
	      (Operator.DepSet.union deps deps',unary_cands,no_unary) }
      ) state l in
  let state' = do_op Nbr.sub state consumed in do_op Nbr.add state' injected

let transform_by_a_rule
      ~get_alg env domain unary_ccs counter state event_kind ?path rule inj =
  let state' =
    update_tokens
      ~get_alg env counter state rule.Primitives.consumed_tokens
      rule.Primitives.injected_tokens in
  update_edges (Environment.signatures env)
	       counter domain unary_ccs inj state' event_kind ?path rule

let apply_unary_rule
      ~rule_id ~get_alg env domain unary_ccs counter state event_kind rule =
  let  (root1,root2 as roots) =
    match
      Mods.Int2Set.random
	(Mods.IntMap.find_default
	   Mods.Int2Set.empty rule_id state.unary_candidates) with
    | None -> failwith "Tried apply_unary_rule with no roots"
    | Some x -> x in
  let () =
    if !Parameter.debugModeOn then
      Format.printf "@[On roots:@ %i@ %i@]@." root1 root2 in
  let cc1 = rule.Primitives.connected_components.(0) in
  let cc2 = rule.Primitives.connected_components.(1) in
  let pair = (min root1 root2,max root1 root2) in
  let candidate =
    match Mods.Int2Map.find_option pair state.unary_pathes with
    | Some (_,x) -> x
    | None -> raise Not_found in
  let cands,pathes = remove_candidate state.unary_candidates state.unary_pathes
				      rule_id roots in
  let deps,unary_cands,_ = state.outdated_elements in
  let state' =
    {state with
      unary_candidates = cands; unary_pathes = pathes;
      outdated_elements =
	(Operator.DepSet.add (Operator.RULE rule_id) deps,unary_cands,false)} in
  let missing_ccs =
    not @@
      Mods.IntSet.mem root1 (Connected_component.Map.find_default
			       Mods.IntSet.empty cc1 state.roots_of_ccs) &&
      Mods.IntSet.mem root2 (Connected_component.Map.find_default
			       Mods.IntSet.empty cc2 state.roots_of_ccs) in
  let root1_ty = match Connected_component.find_root_type cc1 with
    | None -> assert false | Some x -> x in
  match Edges.are_connected ~candidate (Environment.signatures env)
			    state.edges root1_ty root1 root2 with
  | None -> Corrected state'
  | Some _ when missing_ccs -> Corrected state'
  | Some _ as path ->
     let inj1 =
       Connected_component.Matching.reconstruct
	 state'.edges Connected_component.Matching.empty 0 cc1 root1 in
     let inj =
       match inj1 with
       | None -> None
       | Some inj -> Connected_component.Matching.reconstruct
		       state'.edges inj 1 cc2 root2 in
     match inj with
     | None -> Clash
     | Some inj ->
	Success
	  (transform_by_a_rule ~get_alg env domain unary_ccs counter state'
			       event_kind ?path rule inj)

let apply_rule
      ?rule_id ~get_alg env domain unary_ccs counter state event_kind rule =
  let inj,roots =
    Tools.array_fold_left_mapi
      (fun id inj cc ->
       let root =
	 match Mods.IntSet.random
		 (Connected_component.Map.find_default
		    Mods.IntSet.empty cc state.roots_of_ccs) with
	 | None -> failwith "Tried to apply_rule with no root"
	 | Some x -> x in
       (match inj with
       | Some inj ->
	  Connected_component.Matching.reconstruct state.edges inj id cc root
       | None -> None),root)
      (Some Connected_component.Matching.empty)
      rule.Primitives.connected_components in
  let () =
    if !Parameter.debugModeOn then
      Format.printf "@[On roots:@ @[%a@]@]@."
		    (Pp.array Pp.space (fun _ -> Format.pp_print_int)) roots in
  match inj with
  | None -> Clash
  | Some inj ->
     let out =
       transform_by_a_rule
	 ~get_alg env domain unary_ccs counter state event_kind rule inj
     in
     match rule.Primitives.unary_rate with
     | None -> Success out
     | Some _ ->
	try
	  let point = (min roots.(0) roots.(1), max roots.(0) roots.(1)) in
	  let nb_use_cand,candidate =
	    match Mods.Int2Map.find_option point state.unary_pathes with
	    | Some x -> x
	    | None -> raise Not_found in
	  let root0_ty =
	    match Connected_component.find_root_type
		    rule.Primitives.connected_components.(0) with
	    | None -> assert false | Some x -> x in
	  match
	    Edges.are_connected ~candidate (Environment.signatures env)
				state.edges root0_ty roots.(0) roots.(1) with
	  | None ->
	     let rid =
	       match rule_id with None -> assert false | Some rid -> rid in
	     let cands,pathes =
	       remove_candidate state.unary_candidates state.unary_pathes rid
				(roots.(0),roots.(1)) in
	     let state' =
	       {state with unary_candidates = cands; unary_pathes = pathes} in
	     Success (transform_by_a_rule
			~get_alg env domain unary_ccs counter state'
			event_kind rule inj)
	  | Some p ->
	     let state' =
	       if p == candidate then state
	       else {state with
		      unary_pathes =
			Mods.Int2Map.add point (nb_use_cand,p) state.unary_pathes}
	     in Corrected state'
	with Not_found -> Success out

let force_rule
    ~get_alg env domain unary_ccs counter state event_kind rule =
  match apply_rule ~get_alg env domain unary_ccs counter state event_kind rule with
  | (Success out | Corrected out) -> out,None
  | Clash ->
     match all_injections
	     state.edges state.roots_of_ccs rule.Primitives.connected_components
     with
     | [] -> state,Some []
     | h :: t ->
	(transform_by_a_rule
	   ~get_alg env domain unary_ccs counter state event_kind rule h),
	Some t

let print env f state =
  Format.fprintf
    f "@[<v>%a@,%a@]"
    (Edges.print (Environment.signatures env)) state.edges
    (Pp.array Pp.space (fun i f el ->
			Format.fprintf
			  f "%%init: %a <- %a"
			  (Environment.print_token ~env) i Nbr.print el))
    state.tokens

let print_dot env f state =
  Format.fprintf
    f "@[<v>digraph G{@,%a@,%a}@]"
    (Edges.print_dot (Environment.signatures env)) state.edges
    (Pp.array Pp.cut (fun i f el ->
		      Format.fprintf
			f
			"token_%d [label = \"%a (%a)\" , shape=none]"
			i (Environment.print_token ~env) i Nbr.print el))
    state.tokens

let debug_print f state =
  Format.fprintf f "@[<v>%a@,%a@,%a@,%a@]"
		 Edges.debug_print state.edges
		 (Pp.array Pp.space (fun i f el ->
				     Format.fprintf f "token_%i <- %a"
						    i Nbr.print el))
		 state.tokens
		 (print_injections ?sigs:None Format.pp_print_int) state.roots_of_ccs
		 (Pp.set Mods.IntMap.bindings Pp.cut
			 (fun f (rule,roots) ->
			  Format.fprintf f "@[rule_%i ==> %a@]" rule
					 (Pp.set Mods.Int2Set.elements Pp.comma (fun f (x,y) -> Format.fprintf f "(%i,%i)" x y))
					 roots))
		 state.unary_candidates

let add_tracked ccs event_kind tests state =
  match state.story_machinery with
  | None ->
     raise (ExceptionDefn.Internal_Error
	      (Location.dummy_annot "TRACK in non tracking mode"))
  | Some (tcc,x) ->
     let tcc' =
     Array.fold_left
       (fun tcc cc ->
	let acc = Connected_component.Map.find_default [] cc tcc in
	Connected_component.Map.add cc ((event_kind,ccs,tests)::acc) tcc)
       tcc ccs in
     { state with story_machinery = Some (tcc',x) }

let remove_tracked ccs state =
  match state.story_machinery with
  | None ->
     raise (ExceptionDefn.Internal_Error
	      (Location.dummy_annot "TRACK in non tracking mode"))
  | Some (tcc,x) ->
     let tester (_,el,_) =
       not @@
	 Tools.array_fold_lefti
	   (fun i b x -> b && Connected_component.is_equal_canonicals x el.(i))
	   true ccs in
     let tcc' =
     Array.fold_left
       (fun tcc cc ->
	let acc = Connected_component.Map.find_default [] cc tcc in
	match List.filter tester acc with
	| [] -> Connected_component.Map.remove cc tcc
	| l -> Connected_component.Map.add cc l tcc)
       tcc ccs in
     { state with story_machinery = Some (tcc',x) }

let generate_stories logger env state =
  match state.story_machinery with
  | None -> ()
  | Some (_,(infos,steps)) ->
     Compression_main.compress_and_print logger env infos (List.rev steps)
