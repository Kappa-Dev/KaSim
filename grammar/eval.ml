(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

open Ast

let rec compile_alg ~compileModeOn domain (alg,pos) =
  match alg with
  | Alg_expr.KAPPA_INSTANCE ast ->
    begin
      match domain with
      | Some (origin,contact_map,domain) ->
        let domain',ccs =
          Snip.connected_components_sum_of_ambiguous_mixture
            ~compileModeOn contact_map domain ?origin ast in
        let out_ccs = List.map (fun (x,_) -> Array.map fst x) ccs in
        (Some (origin,contact_map,domain'),
         (Alg_expr.KAPPA_INSTANCE out_ccs,pos))
      | None ->
        raise (ExceptionDefn.Internal_Error
                 ("Theoritically pure alg_expr has a mixture",pos))
    end
  | Alg_expr.ALG_VAR i -> (domain,(Alg_expr.ALG_VAR i,pos))
  | Alg_expr.TOKEN_ID i -> (domain,(Alg_expr.TOKEN_ID i,pos))
  | Alg_expr.STATE_ALG_OP (op) -> (domain,(Alg_expr.STATE_ALG_OP (op),pos))
  | Alg_expr.CONST n -> (domain,(Alg_expr.CONST n,pos))
  | Alg_expr.BIN_ALG_OP (op, a, b) ->
    let domain',a' = compile_alg ~compileModeOn domain a in
    let domain'',b' = compile_alg ~compileModeOn domain' b in
    (domain'',(Alg_expr.BIN_ALG_OP (op,a',b'),pos))
  | Alg_expr.UN_ALG_OP (op,a) ->
    let domain',a' = compile_alg ~compileModeOn domain a in
    (domain',(Alg_expr.UN_ALG_OP (op,a'),pos))
  | Alg_expr.IF (cond,yes,no) ->
    let domain',cond' = compile_bool ~compileModeOn domain cond in
    let domain'',yes' = compile_alg ~compileModeOn domain' yes in
    let domain''',no' = compile_alg ~compileModeOn domain'' no in
    (domain''',(Alg_expr.IF (cond',yes',no'),pos))
  | Alg_expr.DIFF_KAPPA_INSTANCE _
    | Alg_expr.DIFF_TOKEN _ ->
    raise
      (ExceptionDefn.Internal_Error
         ("Cannot deal with derivative in expressions",pos))
and compile_bool ~compileModeOn domain = function
  | Alg_expr.TRUE,pos -> (domain,(Alg_expr.TRUE,pos))
  | Alg_expr.FALSE,pos -> (domain,(Alg_expr.FALSE,pos))
  | Alg_expr.BOOL_OP (op,a,b), pos ->
    let domain',a' = compile_bool ~compileModeOn domain a in
    let domain'',b' = compile_bool ~compileModeOn domain' b in
    (domain'',(Alg_expr.BOOL_OP (op,a',b'),pos))
  | Alg_expr.COMPARE_OP (op,a,b),pos ->
    let (domain',a') = compile_alg ~compileModeOn domain a in
    let (domain'',b') = compile_alg ~compileModeOn domain' b in
    (domain'',(Alg_expr.COMPARE_OP (op,a',b'), pos))

let compile_pure_alg ~compileModeOn (alg,pos) =
  snd @@ compile_alg ~compileModeOn None (alg,pos)

let compile_alg ~compileModeOn ?origin contact_map domain (alg,pos) =
  match compile_alg
          ~compileModeOn (Some (origin,contact_map,domain)) (alg,pos) with
  | Some (_, _,domain),alg -> domain,alg
  | None, _ -> failwith "domain has been lost in Expr.compile_alg"

let compile_bool ~compileModeOn ?origin contact_map domain (alg,pos) =
  match compile_bool
          ~compileModeOn (Some (origin,contact_map,domain)) (alg,pos) with
  | Some (_, _,domain),alg -> domain,alg
  | None, _ -> failwith "domain has been lost in Expr.compile_alg"

let tokenify ~compileModeOn contact_map domain l =
  List.fold_right
    (fun (alg_expr,id) (domain,out) ->
       let (domain',alg) =
         compile_alg ~compileModeOn contact_map domain alg_expr in
       (domain',(alg,id)::out)
    ) l (domain,[])

(* transform an LKappa rule into a Primitives rule *)
let rules_of_ast
    ?deps_machinery ~compileModeOn
    contact_map domain ~syntax_ref (rule,_) =
  let domain',delta_toks =
    tokenify ~compileModeOn contact_map domain rule.LKappa.r_delta_tokens in
  (*  let one_side syntax_ref label (domain,deps_machinery,unary_ccs,acc)
        rate unary_rate lhs rhs rm add =*)
  let origin,deps =
    match deps_machinery with
    | None -> None,None
    | Some (o,d) -> Some o, Some d in
  let unary_infos =
    let crp = compile_pure_alg ~compileModeOn rule.LKappa.r_rate in
    match rule.LKappa.r_un_rate with
    | None -> fun _ uncc -> crp,None,uncc
    | Some ((_,pos as rate),dist) ->
      let dist' = match dist with
        | None -> None
        | Some d ->
           let (d', _) = compile_pure_alg ~compileModeOn d in
           Some d' in
      let unrate = compile_pure_alg ~compileModeOn rate in
      fun ccs uncc ->
        match Array.length ccs with
        | (0 | 1) ->
          let () =
            ExceptionDefn.warning
              ~pos
              (fun f ->
                 Format.pp_print_text
                   f "Useless molecular ambiguity, the rules is \
always considered as unary.") in
          unrate,None,uncc
        | 2 ->
          crp,Some (unrate, dist'),
          Pattern.Set.add ccs.(0) (Pattern.Set.add ccs.(1) uncc)
        | n ->
          raise (ExceptionDefn.Malformed_Decl
                   ("Unary rule does not deal with "^
                    string_of_int n^" connected components.",pos)) in
  let build deps un_ccs (origin,ccs,syntax,(neg,pos)) =
    let ccs' = Array.map fst ccs in
    let rate,unrate,un_ccs' = unary_infos ccs' un_ccs in
    Option_util.map
      (fun x ->
         let origin =
           match origin with Some o -> o | None -> failwith "ugly Eval.rule_of_ast" in
         let x' =
           match unrate with
           | None -> x
           | Some (ur,_) -> Alg_expr.add_dep x origin ur in
         Alg_expr.add_dep x' origin rate)
      deps,un_ccs',{
      Primitives.unary_rate = unrate;
      Primitives.rate = rate;
      Primitives.connected_components = ccs';
      Primitives.removed = neg;
      Primitives.inserted = pos;
      Primitives.delta_tokens = delta_toks;
      Primitives.syntactic_rule = syntax_ref;
      Primitives.instantiations = syntax;
    } in
  let rule_mixtures,(domain',origin') =
    Snip.connected_components_sum_of_ambiguous_rule
      ~compileModeOn contact_map
      domain' ?origin rule.LKappa.r_mix rule.LKappa.r_created in
  let deps_algs',unary_ccs',rules_l =
    List.fold_right
      (fun r (deps_algs,un_ccs,out) ->
         let deps_algs',un_ccs',r'' = build deps_algs un_ccs r in
         deps_algs',un_ccs',r''::out)
      rule_mixtures (deps,Pattern.Set.empty,[]) in
  domain',(match origin' with
      | None -> None
      | Some o -> Some (o,
                        match deps_algs' with
                        | Some d -> d
                        | None -> failwith "ugly Eval.rule_of_ast")),
  unary_ccs',rules_l

let obs_of_result ~compileModeOn contact_map domain res =
  let time =
    Locality.dummy_annot (Alg_expr.STATE_ALG_OP Operator.TIME_VAR) in
  match res.observables with
  | [] -> domain,[time]
  | _ :: _ ->
    List.fold_left
      (fun (domain,cont) alg_expr ->
         let (domain',alg_pos) =
           compile_alg ~compileModeOn contact_map domain alg_expr in
         domain',alg_pos :: cont)
      (domain,[time]) res.observables

let compile_print_expr ~compileModeOn contact_map domain ex =
  List.fold_right
    (fun el (domain,out) ->
       match el with
       | Primitives.Str_pexpr s -> (domain,Primitives.Str_pexpr s::out)
       | Primitives.Alg_pexpr ast_alg ->
         let (domain', alg) =
           compile_alg ~compileModeOn contact_map domain ast_alg in
         (domain',(Primitives.Alg_pexpr alg::out)))
    ex (domain,[])

let cflows_of_label
    origin ~compileModeOn
    contact_map domain on algs rules (label,pos) rev_effects =
  let adds tests l x =
    if on then Primitives.CFLOW (Some label,x,tests) :: l
    else Primitives.CFLOWOFF x :: l in
  let mix =
    try
      let (_,(rule,_)) =
        List.find (function None,_ -> false | Some (l,_),_ -> l=label) rules in
      LKappa.to_maintained rule.LKappa.r_mix
    with Not_found ->
    try let (_,(var,_)) = List.find (fun ((l,_),_) -> l = label) algs in
      match var with
      | Alg_expr.KAPPA_INSTANCE mix -> mix
      | (Alg_expr.BIN_ALG_OP _ | Alg_expr.UN_ALG_OP _ | Alg_expr.STATE_ALG_OP _
        | Alg_expr.ALG_VAR _ | Alg_expr.TOKEN_ID _ | Alg_expr.CONST _
        | Alg_expr.IF _ | Alg_expr.DIFF_TOKEN _
        | Alg_expr.DIFF_KAPPA_INSTANCE _) -> raise Not_found
    with Not_found ->
      raise (ExceptionDefn.Malformed_Decl
               ("Label '" ^ label ^
                "' does not refer to a non ambiguous Kappa expression"
               ,pos)) in
  let domain',ccs =
    Snip.connected_components_sum_of_ambiguous_mixture
      ~compileModeOn contact_map domain ~origin mix in
  (domain',
   List.fold_left (fun x (y,t) -> adds t x (Array.map fst y)) rev_effects ccs)

let rule_effect ~compileModeOn contact_map domain alg_expr
    (mix,created,tks) mix_pos rev_effects =
  let ast_rule =
    { LKappa.r_mix = mix; LKappa.r_created = created;
      LKappa.r_delta_tokens = tks; LKappa.r_un_rate = None;
      LKappa.r_rate = Alg_expr.const Nbr.zero; LKappa.r_editStyle = true;
    } in
  let (domain',alg_pos) =
    compile_alg ~compileModeOn contact_map domain alg_expr in
  let domain'',_,_,elem_rules =
    rules_of_ast
      ~compileModeOn contact_map domain' ~syntax_ref:0 (ast_rule,mix_pos) in
  let elem_rule = match elem_rules with
    | [ r ] -> r
    | _ ->
      raise
        (ExceptionDefn.Malformed_Decl
           ("Ambiguous rule in perturbation is impossible",mix_pos)) in
  (domain'',
   (Primitives.ITER_RULE (alg_pos, elem_rule))::rev_effects)

let effects_of_modif
    ast_algs ast_rules origin ~compileModeOn
    contact_map (domain,rev_effects) = function
  | INTRO (alg_expr, (ast_mix,mix_pos)) ->
    rule_effect ~compileModeOn contact_map domain alg_expr
      ([],LKappa.to_raw_mixture (Pattern.PreEnv.sigs domain) ast_mix,[])
      mix_pos rev_effects
  | DELETE (alg_expr, (ast_mix, mix_pos)) ->
    rule_effect ~compileModeOn contact_map domain alg_expr
      (LKappa.to_erased (Pattern.PreEnv.sigs domain) ast_mix,[],[])
      mix_pos rev_effects
  | UPDATE ((i, _), alg_expr) ->
    let (domain', alg_pos) =
      compile_alg ~compileModeOn contact_map domain alg_expr in
    (domain',(Primitives.UPDATE (i, alg_pos))::rev_effects)
  | UPDATE_TOK ((tk_id,tk_pos),alg_expr) ->
    rule_effect ~compileModeOn contact_map domain
      (Alg_expr.const Nbr.one)
      ([],[],
       [Locality.dummy_annot
          (Alg_expr.BIN_ALG_OP
             (Operator.MINUS,alg_expr,
              Locality.dummy_annot (Alg_expr.TOKEN_ID tk_id))), tk_id])
      tk_pos rev_effects
  | SNAPSHOT pexpr ->
    let (domain',pexpr') =
      compile_print_expr ~compileModeOn contact_map domain pexpr in
    (*when specializing snapshots to particular mixtures, add variables below*)
    (domain', (Primitives.SNAPSHOT pexpr')::rev_effects)
  | STOP pexpr ->
    let (domain',pexpr') =
      compile_print_expr ~compileModeOn contact_map domain pexpr in
    (domain', (Primitives.STOP pexpr')::rev_effects)
  | CFLOWLABEL (on,lab) ->
    cflows_of_label origin ~compileModeOn
      contact_map domain on ast_algs ast_rules lab rev_effects
  | CFLOWMIX (on,(ast,_)) ->
    let adds tests l x =
      if on then Primitives.CFLOW (None,x,tests) :: l
      else Primitives.CFLOWOFF x :: l in
    let domain',ccs =
      Snip.connected_components_sum_of_ambiguous_mixture
        ~compileModeOn contact_map domain ~origin ast in
    (domain',
     List.fold_left (fun x (y,t) -> adds t x (Array.map fst y)) rev_effects ccs)
  | FLUX (rel,pexpr) ->
    let (domain',pexpr') =
      compile_print_expr ~compileModeOn contact_map domain pexpr in
    (domain', (Primitives.FLUX (rel,pexpr'))::rev_effects)
  | FLUXOFF pexpr ->
    let (domain',pexpr') =
      compile_print_expr ~compileModeOn contact_map domain pexpr in
    (domain', (Primitives.FLUXOFF pexpr')::rev_effects)
  | Ast.PRINT (pexpr,print) ->
    let (domain',pexpr') =
      compile_print_expr ~compileModeOn contact_map domain pexpr in
    let (domain'',print') =
      compile_print_expr ~compileModeOn contact_map domain' print in
    (domain'', (Primitives.PRINT (pexpr',print'))::rev_effects)
  | PLOTENTRY ->
    (domain, (Primitives.PLOTENTRY)::rev_effects)

let effects_of_modifs
    ast_algs ast_rules origin ~compileModeOn contact_map domain l =
  let domain',rev_effects =
    List.fold_left
      (effects_of_modif ast_algs ast_rules origin ~compileModeOn contact_map)
      (domain,[]) l in
  domain',List.rev rev_effects

let compile_modifications_no_track =
  effects_of_modifs [] [] (Operator.PERT (-1))

let pert_of_result
    ast_algs ast_rules alg_deps ~compileModeOn contact_map domain res =
  let (domain, out_alg_deps, _, lpert,tracking_enabled) =
    List.fold_left
      (fun (domain, alg_deps, p_id, lpert, tracking_enabled)
        ((pre_expr, modif_expr_list, opt_post),_) ->
        let origin = Operator.PERT p_id in
        let (domain',pre) =
          compile_bool ~compileModeOn ~origin contact_map domain pre_expr in
        let alg_deps' = Alg_expr.add_dep_bool alg_deps origin pre in
        let (domain, effects) =
          effects_of_modifs
            ast_algs ast_rules origin ~compileModeOn
            contact_map domain' modif_expr_list in
        let domain,opt =
          match opt_post with
          | None -> (domain,None)
          | Some post_expr ->
            let (domain',(post,post_pos)) =
              compile_bool ~compileModeOn contact_map domain post_expr in
            (domain',Some (post,post_pos))
        in
        let has_tracking =
          tracking_enabled || List.exists
            (function
              | Primitives.CFLOW _ -> true
              | (Primitives.CFLOWOFF _ | Primitives.PRINT _ |
                 Primitives.UPDATE _ | Primitives.SNAPSHOT _
                | Primitives.FLUX _ | Primitives.FLUXOFF _ |
                Primitives.PLOTENTRY | Primitives.STOP _ |
                Primitives.ITER_RULE _) -> false) effects in
        let pert =
          { Primitives.precondition = pre;
            Primitives.effect = effects;
            Primitives.abort = opt;
          } in
        (domain, alg_deps', succ p_id, pert::lpert,has_tracking)
      )
      (domain, alg_deps, 0, [], false) res.perturbations
  in
  (domain, out_alg_deps, List.rev lpert,tracking_enabled)

let compile_inits ?rescale ~compileModeOn contact_map env inits =
  let init_l,_ =
    List_util.fold_right_map
      (fun (_opt_vol,alg,init_t) preenv -> (*TODO deal with volumes*)
         let () =
           if Alg_expr.has_mix ~var_decls:(Model.get_alg env) (fst alg) then
             raise
               (ExceptionDefn.Malformed_Decl
                  ("Initial quantities cannot depend on a number of occurence",
                   snd alg)) in
         let alg = match rescale with
           | None -> alg
           | Some r -> Alg_expr.mult alg (Alg_expr.float r) in
         match init_t with
         | INIT_MIX ast,mix_pos ->
           let sigs = Model.signatures env in
           let (preenv',alg') =
             compile_alg ~compileModeOn contact_map preenv alg in
           let fake_rule = {
             LKappa.r_mix = [];
             LKappa.r_created = LKappa.to_raw_mixture sigs ast;
             LKappa.r_delta_tokens = [];
             LKappa.r_rate = Alg_expr.const Nbr.zero;
             LKappa.r_un_rate = None;
             LKappa.r_editStyle = true;
           } in
           let preenv'',state' =
             match
               rules_of_ast ~compileModeOn contact_map
                 preenv' ~syntax_ref:0 (fake_rule,mix_pos)
             with
             | domain'',_,_,[ compiled_rule ] ->
               (fst alg',compiled_rule,mix_pos),domain''
             | _,_,_,_ ->
               raise (ExceptionDefn.Malformed_Decl
                        (Format.asprintf
                           "initial mixture %a is partially defined"
                           (LKappa.print_rule_mixture sigs ~ltypes:false) ast,
                         mix_pos)) in
           preenv'',state'
         | INIT_TOK tk_id,pos_tk ->
           let fake_rule = {
             LKappa.r_mix = []; LKappa.r_created = [];
             LKappa.r_delta_tokens = [(alg, tk_id)];
             LKappa.r_rate = Alg_expr.const Nbr.zero;
             LKappa.r_un_rate = None; LKappa.r_editStyle = false;
           } in
           match
             rules_of_ast
               ~compileModeOn contact_map preenv ~syntax_ref:0
               (Locality.dummy_annot fake_rule)
           with
           | domain'',_,_,[ compiled_rule ] ->
             (Alg_expr.CONST Nbr.one,compiled_rule,pos_tk),domain''
           | _,_,_,_ -> assert false
      ) inits (Pattern.PreEnv.empty (Model.signatures env)) in
  init_l

let compile_alg_vars ~compileModeOn contact_map domain vars =
  Tools.array_fold_left_mapi
    (fun i domain (lbl_pos,ast) ->
       let (domain',alg) =
         compile_alg
           ~compileModeOn ~origin:(Operator.ALG i) contact_map domain ast
       in (domain',(lbl_pos,alg))) domain
    (Array.of_list vars)

let compile_rules alg_deps ~compileModeOn contact_map domain rules =
  match
    List.fold_left
      (fun (domain,syntax_ref,deps_machinery,unary_cc,acc) (_,rule) ->
         let (domain',origin',extra_unary_cc,cr) =
           rules_of_ast ?deps_machinery ~compileModeOn contact_map domain
             ~syntax_ref rule in
         (domain',succ syntax_ref,origin',
          Pattern.Set.union unary_cc extra_unary_cc,
          List.append cr acc))
      (domain,1,Some (Operator.RULE 0,alg_deps),
       Pattern.Set.empty,[])
      rules with
  | fdomain,_,Some (_,falg_deps),unary_cc,frules ->
    fdomain,falg_deps,List.rev frules,unary_cc
  | _, _, None, _, _ ->
    failwith "The origin of Eval.compile_rules has been lost"

(*let translate_contact_map sigs kasa_contact_map =
  let wdl = Locality.dummy_annot in
  let sol = Array.init
      (Signature.size sigs)
      (fun i -> Array.make (Signature.arity sigs i) ([],[])) in
  let () =
    Mods.StringMap.iter
      (fun agent_name sites ->
         let id_a = Signature.num_of_agent (wdl agent_name) sigs in
         Mods.StringMap.iter
           (fun site_name (states,links) ->
              let id_s =
                Signature.num_of_site
                  ~agent_name (wdl site_name) (Signature.get sigs id_a) in
              sol.(id_a).(id_s) <-
                (List.map
                   (fun state -> Signature.num_of_internal_state
                       id_s (wdl state) (Signature.get sigs id_a))
                   states,
                 List.map
                   (fun (agent_name,b) ->
                      let id_a =
                        Signature.num_of_agent (wdl agent_name) sigs in
                      let id_b =
                        Signature.num_of_site
                          ~agent_name (wdl b) (Signature.get sigs id_a) in
                      (id_a,id_b))
                   links)) sites) kasa_contact_map in
  sol

let init_kasa called_from sigs result =
  let pre_kasa_state = Export_to_KaSim.init ~compil:result ~called_from () in
  let kasa_state,contact_map = Export_to_KaSim.get_contact_map pre_kasa_state in
  let () = Export_to_KaSim.dump_errors_light kasa_state in
  translate_contact_map sigs contact_map,
  Export_to_KaSim.flush_errors kasa_state
*)
let compile ~outputs ~pause ~return ~max_sharing ~compileModeOn ?overwrite_init
    ?rescale_init sigs_nd tk_nd contact_map result =
  outputs (Data.Log "+ Building initial simulation conditions...");
  let preenv = Pattern.PreEnv.empty sigs_nd in
  outputs (Data.Log "\t -variable declarations");
  let preenv',alg_a =
    compile_alg_vars ~compileModeOn contact_map preenv result.Ast.variables in
  let alg_nd = NamedDecls.create alg_a in
  let alg_deps = Alg_expr.setup_alg_vars_rev_dep tk_nd alg_a in

  pause @@ fun () ->
  outputs (Data.Log "\t -rules");
  let (preenv',alg_deps',compiled_rules,cc_unaries) =
    compile_rules
      alg_deps ~compileModeOn contact_map preenv' result.Ast.rules in
  let rule_nd = Array.of_list compiled_rules in

  pause @@ fun () ->
  outputs (Data.Log "\t -perturbations");
  let (preenv,alg_deps'',pert,has_tracking) =
    pert_of_result
      result.variables result.rules alg_deps' ~compileModeOn
      contact_map preenv' result in

  pause @@ fun () ->
  outputs (Data.Log "\t -observables");
  let preenv,obs =
    obs_of_result ~compileModeOn contact_map preenv result in

  outputs (Data.Log "\t -update_domain construction");
  pause @@ fun () ->
  let domain,dom_stats = Pattern.finalize ~max_sharing preenv contact_map in
  outputs (Data.Log ("\t "^string_of_int dom_stats.Pattern.PreEnv.nodes^
                     " (sub)observables "^
                     string_of_int dom_stats.Pattern.PreEnv.nav_steps^
                     " navigation steps"));

  let env =
    Model.init domain tk_nd alg_nd alg_deps''
      (Array.of_list result.rules,rule_nd,cc_unaries)
      (Array.of_list (List.rev obs)) (Array.of_list pert) contact_map in

  outputs (Data.Log "\t -initial conditions");
  pause @@ fun () ->
  let init_l =
    compile_inits
      ?rescale:rescale_init ~compileModeOn contact_map
      env (Option_util.unsome result.Ast.init overwrite_init) in
  return (env,has_tracking,init_l)

let build_initial_state
    ~bind ~return ~outputs counter env ~with_trace ~with_delta_activities
    random_state init_l =
  let stops = Model.fold_perturbations
      (fun i acc p ->
         let s = Primitives.stops_of_perturbation
             (Model.all_dependencies env) p in
         List.fold_left (fun acc s -> (s,i)::acc) acc s)
      [] env in
  let graph0 = Rule_interpreter.empty
      ~with_trace random_state env counter in
  let state0 = State_interpreter.empty ~with_delta_activities env stops in
  State_interpreter.initialize
    ~bind ~return ~outputs env counter graph0 state0 init_l
