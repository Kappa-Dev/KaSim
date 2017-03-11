(**
   * algebraic_construction.ml
   * openkappa
   * Jérôme Feret, projet Abstraction/Antique, INRIA Paris-Rocquencourt
   *
   * Creation: September, the 27th of 2015
   * Last modification: Time-stamp: <Mar 11 2017>
   * *
   * algebraic check for the influence map.
   *
   * Copyright 2015 Institut National de Recherche en Informatique et
   * en Automatique.  All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

exception False of Exception.method_handler

let check parameters error _handler mixture1 mixture2 (i,j) =
  let add (n1,n2) error to_do (inj1,inj2) =
    let im1 =
      Ckappa_sig.Agent_id_setmap.Map.find_option
        n1
        inj1
    in
    error,match im1
    with
    | Some n2' when n2 = n2' -> Some (to_do, inj1, inj2)
    | Some _ -> None
    | None ->
      begin
        let im2 =
          Ckappa_sig.Agent_id_setmap.Map.find_option
            n2
            inj2
        in
        match im2
        with Some _ -> None
           | None ->
             let inj1 =
               Ckappa_sig.Agent_id_setmap.Map.add
                 n1
                 n2
                 inj1
             in
             let inj2 =
               Ckappa_sig.Agent_id_setmap.Map.add
                 n2
                 n1
                 inj2
             in
             Some ((n1, n2) :: to_do, inj1, inj2)
      end
  in

  let rec check_agent error to_do already_done =
    match to_do with
    | [] -> error,Some already_done
    | (h1,h2) :: t when Ckappa_sig.compare_agent_id h1 Ckappa_sig.dummy_agent_id < 0
                        ||
                        Ckappa_sig.compare_agent_id h2 Ckappa_sig.dummy_agent_id < 0
      ->
      check_agent error t already_done
    | (h1,h2)::t ->
      begin
        let error,view1 =
          Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.get
            parameters error h1 mixture1.Cckappa_sig.views
        in
        let error,view2 =
          Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.get
            parameters error h2 mixture2.Cckappa_sig.views
        in
        let error,bonds1 =
          Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
            parameters error h1 mixture1.Cckappa_sig.bonds
        in
        let error,bonds2 =
          Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.unsafe_get
            parameters error h2 mixture2.Cckappa_sig.bonds
        in
        check_interface error view1 view2 bonds1 bonds2 t already_done
      end

  and deal_with error iter2 ag1 ag2 bonds1 bonds2 (to_do,already_done) =
    let bonds1 =
      match bonds1 with Some bonds1 -> bonds1 | None -> Ckappa_sig.Site_map_and_set.Map.empty
    in
    let bonds2 =
      match bonds2 with Some bonds2 -> bonds2 | None -> Ckappa_sig.Site_map_and_set.Map.empty
    in
    let error,bool =
      try
        let error =
          iter2
            parameters error
            (fun _ error _ port1 port2 ->
               let range1 = port1.Cckappa_sig.site_state in
               let range2 = port2.Cckappa_sig.site_state in
               if not (range1.Cckappa_sig.max < range2.Cckappa_sig.min ||
                       range2.Cckappa_sig.max < range1.Cckappa_sig.min)
               then error
               else raise (False error))
            ag1.Cckappa_sig.agent_interface
            ag2.Cckappa_sig.agent_interface
        in error, true
      with
        False error -> error, false
    in
    if bool
    then
      try
        let error,(to_do,already_done) =
          Ckappa_sig.Site_map_and_set.Map.fold2_sparse parameters error
            (fun _ error _ port1 port2 (to_do,already_done) ->
               if port1.Cckappa_sig.site = port2.Cckappa_sig.site
               then
                 match
                   add
                     (port1.Cckappa_sig.agent_index,
                      port2.Cckappa_sig.agent_index)
                     error
                     to_do
                     already_done
                 with
                 | error,None -> raise (False error)
                 | error,Some (todo,inj1,inj2) -> (error,(todo,(inj1,inj2)))
               else
                 raise (False error)
            )
            bonds1
            bonds2
            (to_do,already_done)
        in error,(true,(to_do,already_done))
      with
        False error -> error,(false,(to_do,already_done))
    else
      error,(bool,(to_do,already_done))


  and check_interface error ag1 ag2 bonds1 bonds2 to_do already_done =

    let error,(bool,(to_do,already_done)) =
      match
        ag1,ag2
      with
      | None,_ | _,None ->
        Exception.warn
          parameters error __POS__
          ~message:"Should not scan empty agents..." Exit (true,(to_do,already_done))
      | Some ag1,Some ag2 ->
        begin
          match ag1
          with
          | Cckappa_sig.Ghost->
            Exception.warn
              parameters error __POS__
              ~message:"Should not scan ghost agents..." Exit (true,(to_do,already_done))
          | Cckappa_sig.Unknown_agent _ -> raise (False error)
          | Cckappa_sig.Dead_agent (ag1,_,l11,l12) ->
            begin
              match ag2 with
              | Cckappa_sig.Unknown_agent _ -> raise (False error)
              | Cckappa_sig.Ghost ->
                Exception.warn
                  parameters error __POS__
                  ~message:"Should not scan ghost agents..."
                  Exit (true,(to_do,already_done))
              | Cckappa_sig.Dead_agent (ag2,_s2,l21,l22) ->
                begin
                  let error,(_bool,(to_do,already_done)) =
                    deal_with error
                      (fun parameter error ->
                         Ckappa_sig.Site_map_and_set.Map.iter2
                           parameter error
                           (fun _parameter error site _ ->
                              if Ckappa_sig.Site_map_and_set.Map.mem site l22 ||
                                 Ckappa_sig.Site_map_and_set.Map.mem site l21
                              then raise (False error)
                              else error)
                           (fun _parameter error site _  ->
                              if Ckappa_sig.Site_map_and_set.Map.mem site l12 ||
                                 Ckappa_sig.Site_map_and_set.Map.mem site l22
                              then raise (False error)
                              else error))
                      ag1
                      ag2
                      bonds1
                      bonds2
                      (to_do,already_done) in
                  (* to do check consistency of dead sites *)
                  error,(true,(to_do,already_done))
                end
              | Cckappa_sig.Agent ag2 ->
                deal_with error
                  (fun parameter error ->
                     Ckappa_sig.Site_map_and_set.Map.iter2
                       parameter error
                       (fun _ error _ _ -> error)
                       (fun _parameter error site _  ->
                          if Ckappa_sig.Site_map_and_set.Map.mem site l11 ||
                             Ckappa_sig.Site_map_and_set.Map.mem site l12
                          then raise (False error)
                          else error))
                  ag1
                  ag2
                  bonds1
                  bonds2
                  (to_do,already_done)

            end
          | Cckappa_sig.Agent ag1 ->
            begin
              match ag2 with
              | Cckappa_sig.Unknown_agent _ -> raise (False error)
              | Cckappa_sig.Ghost ->
                Exception.warn
                  parameters error __POS__
                  ~message:"Should not scan ghost agents..."
                  Exit (true,(to_do,already_done))
              | Cckappa_sig.Dead_agent (ag2,_,l21,l22) ->
                begin
                  begin
                    deal_with error
                      (fun parameter error ->
                         Ckappa_sig.Site_map_and_set.Map.iter2
                           parameter error
                           (fun _parameter error site _ ->
                              if Ckappa_sig.Site_map_and_set.Map.mem site l22 ||
                                 Ckappa_sig.Site_map_and_set.Map.mem site l21
                              then raise (False error)
                              else error)
                           (fun _ error _ _  -> error))
                      ag1
                      ag2
                      bonds1
                      bonds2
                      (to_do,already_done)
                  end
                end
              | Cckappa_sig.Agent ag2 ->
                deal_with error Ckappa_sig.Site_map_and_set.Map.iter2_sparse
                  ag1 ag2 bonds1 bonds2 (to_do,already_done)
            end
        end
    in
    if bool
    then
      check_agent error to_do already_done
    else
      error, None
  in
  let error,ouput = add (i,j) error []
      (Ckappa_sig.Agent_id_setmap.Map.empty, Ckappa_sig.Agent_id_setmap.Map.empty)
  in
  match ouput
  with
    None ->
    Exception.warn
      parameters error __POS__
      ~message:"Missing rule"
      Exit None
  | Some(_,inj1,inj2) -> check_agent error [i,j] (inj1,inj2)

exception Pass of Exception.method_handler

let filter_influence parameters error handler compilation map bool =
  let nrules = Handler.nrules parameters error handler in
  let get_var v =
    match
      snd (v.Cckappa_sig.e_variable)
    with
    | Alg_expr.KAPPA_INSTANCE(mixture), _ -> error,mixture
    | (Alg_expr.IF _ | Alg_expr.BIN_ALG_OP _ | Alg_expr.UN_ALG_OP _
      | Alg_expr.STATE_ALG_OP _ | Alg_expr.ALG_VAR _ | Alg_expr.TOKEN_ID _
      | Alg_expr.CONST _
      | Alg_expr.DIFF_KAPPA_INSTANCE _ | Alg_expr.DIFF_TOKEN _ ),_
      ->
      let error,() =
        Exception.warn
          parameters error __POS__
          ~message:"Composite observable"
          Exit ()
      in raise (Pass error)
  in
  let get_lhs r =
    r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_lhs
  in
  let get_rhs r =
    r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_rhs
  in
  let get_bool = if bool then get_rhs else get_lhs in

  let check_influence_rule_mixt error rule1 mixt  pos =
    let updt_pos ((x:Ckappa_sig.c_agent_id), (y:Ckappa_sig.c_agent_id)) =
      (if bool &&
          Ckappa_sig.compare_agent_id x
            (Ckappa_sig.agent_id_of_int rule1.Cckappa_sig.e_rule_c_rule.Cckappa_sig.prefix)
          >= 0
       then
         Ckappa_sig.add_agent_id
           x
           rule1.Cckappa_sig.e_rule_c_rule.Cckappa_sig.delta
       else x
      ),
      y
    in
    check
      parameters
      error
      handler
      (get_bool rule1)
      mixt
      (updt_pos pos)
  in
  Ckappa_sig.PairRule_setmap.Map.fold
    (fun (a,b) couple (error,map') ->
       try
         begin
           let error,rule1 =
             Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
               parameters
               error
               a
               compilation.Cckappa_sig.rules
           in
           let error,r1 =
             match rule1
             with
             | None ->
               let error,() =
                 Exception.warn
                   parameters error __POS__
                   ~message:"Missing rule"
                   Exit ()
               in raise (Pass error)
             | Some r -> error,r
           in
           let error,mixt =
             if
               Ckappa_sig.compare_rule_id b (Ckappa_sig.rule_id_of_int nrules) < 0
             then
               begin
                 let error,rule2 =
                   Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
                     parameters
                     error
                     b
                     compilation.Cckappa_sig.rules
                 in
                 match rule2 with
                 | None ->
                   let error,() =
                     Exception.warn
                       parameters error __POS__
                       ~message:("Missing rule"^ (Ckappa_sig.string_of_rule_id b))
                       Exit ()
                   in raise (Pass error)
                 | Some r -> error, get_lhs r
               end
             else
               begin
                 let error,var =
                   Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
                     parameters
                     error
                     (Ckappa_sig.sub_rule_id b nrules)
                     compilation.Cckappa_sig.variables
                 in
                 match var with
                 | None ->
                   let error,() =
                     Exception.warn
                       parameters error __POS__
                       ~message:("Missing var" ^(Ckappa_sig.string_of_rule_id b))
                       Exit ()
                   in raise (Pass error)
                 | Some v -> get_var v
               end
           in
           let error,couple' =
             try
               let error,couple' =
                 Quark_type.Labels.filter_couple
                   parameters
                   error
                   handler
                   (fun error a b  ->
                      match
                        check_influence_rule_mixt error
                        r1
                        mixt
                        (Ckappa_sig.agent_id_of_int a,
                         Ckappa_sig.agent_id_of_int b)
                      with
                      | error, Some _ -> error, true
                      | error, None -> error, false
                   )
                   couple
               in
               error,couple'
             with Exit -> error,couple
           in
           if Quark_type.Labels.is_empty_couple couple'
           then  error,map'
           else error,
                Ckappa_sig.PairRule_setmap.Map.add
                  (a,b) couple' map'
         end
       with Pass error -> (error,map')
    )
    map
    (error,
     Ckappa_sig.PairRule_setmap.Map.empty
    )


let filter_influence_high maybe_reachable
    parameters handler error compilation
    static dynamic
    map bool =
  let nrules = Handler.nrules parameters error handler in

  let get_var v =
    match
      snd (v.Cckappa_sig.e_variable)
    with
    | Alg_expr.KAPPA_INSTANCE(mixture), _ -> error,mixture
    | (Alg_expr.IF _ | Alg_expr.BIN_ALG_OP _ | Alg_expr.UN_ALG_OP _
      | Alg_expr.STATE_ALG_OP _ | Alg_expr.ALG_VAR _
      | Alg_expr.DIFF_KAPPA_INSTANCE _ | Alg_expr.DIFF_TOKEN _
      | Alg_expr.TOKEN_ID _
      | Alg_expr.CONST _) ,_     ->
      let error,() =
        Exception.warn
          parameters error __POS__
          ~message:"Composite observable"
          Exit ()
      in raise (Pass error)
  in
  let get_lhs r =
    r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_lhs
  in
  let get_rhs r =
    r.Cckappa_sig.e_rule_c_rule.Cckappa_sig.rule_rhs
  in
  let get_bool = if bool then get_rhs else get_lhs in

  let check_influence_rule_mixt error rule1 mixt  pos =
    let updt_pos ((x:Ckappa_sig.c_agent_id), (y:Ckappa_sig.c_agent_id)) =
      (if bool &&
          Ckappa_sig.compare_agent_id x
            (Ckappa_sig.agent_id_of_int rule1.Cckappa_sig.e_rule_c_rule.Cckappa_sig.prefix)
          >= 0
       then
         Ckappa_sig.add_agent_id
           x
           rule1.Cckappa_sig.e_rule_c_rule.Cckappa_sig.delta
       else x
      ),
      y
    in
    check
      parameters
      error
      handler
      (get_bool rule1)
      mixt
      (updt_pos pos)
  in
  Ckappa_sig.PairRule_setmap.Map.fold
    (fun (a,b) couple ((error,dynamic),map') ->
       try
         begin
           let error,rule1 =
             Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
               parameters
               error
               a
               compilation.Cckappa_sig.rules
           in
           let error,r1 =
             match rule1
             with
             | None ->
               let error,() =
                 Exception.warn
                   parameters error __POS__
                   ~message:"Missing rule"
                   Exit ()
               in raise (Pass error)
             | Some r -> error,r
           in
           let error,mixt =
             if
               Ckappa_sig.compare_rule_id b (Ckappa_sig.rule_id_of_int nrules) < 0
             then
               begin
                 let error,rule2 =
                   Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
                     parameters
                     error
                     b
                     compilation.Cckappa_sig.rules
                 in
                 match rule2 with
                 | None ->
                   let error,() =
                     Exception.warn
                       parameters error __POS__
                       ~message:("Missing rule"^ (Ckappa_sig.string_of_rule_id b))
                       Exit ()
                   in raise (Pass error)
                 | Some r -> error, get_lhs r
               end
             else
               begin
                 let error,var =
                   Ckappa_sig.Rule_nearly_Inf_Int_storage_Imperatif.get
                     parameters
                     error
                     (Ckappa_sig.sub_rule_id b nrules)
                     compilation.Cckappa_sig.variables
                 in
                 match var with
                 | None ->
                   let error,() =
                     Exception.warn
                       parameters error __POS__
                       ~message:("Missing var" ^(Ckappa_sig.string_of_rule_id b))
                       Exit ()
                   in raise (Pass error)
                 | Some v -> get_var v
               end
           in
           let (error,dynamic),couple' =
             try
               let (error,dynamic),couple' =
                 Quark_type.Labels.filter_couple
                   parameters
                   (error, dynamic)
                   handler
                   (fun (error,dynamic) a b  ->
                      match
                        check_influence_rule_mixt error
                        r1
                        mixt
                        (Ckappa_sig.agent_id_of_int a,
                         Ckappa_sig.agent_id_of_int b)
                      with
                      | error, None -> (error, dynamic), false
                      | error, Some (_inj1,inj2) ->
                        let error, n = Ckappa_sig.Agent_id_quick_nearly_Inf_Int_storage_Imperatif.fold
                            parameters
                            error
                            (fun _parameters error i _ sol ->
                               error,
                               if Ckappa_sig.compare_agent_id i sol < 0 then sol else i)
                            (get_bool r1).Cckappa_sig.views
                            Ckappa_sig.dummy_agent_id
                        in
                        let f _parameters error i =
                          match Ckappa_sig.Agent_id_setmap.Map.find_option
                                   i inj2
                          with
                          | None ->
                            error, (Ckappa_sig.agent_id_of_int ((Ckappa_sig.int_of_agent_id
                                                                   i)+
                                                                (Ckappa_sig.int_of_agent_id n) +1))
                          | Some j when Ckappa_sig.compare_agent_id j Ckappa_sig.dummy_agent_id < 0 -> (* check if we can improve in case of negative update, there should be a bond between j and this agent *)
                            error, (Ckappa_sig.agent_id_of_int ((Ckappa_sig.int_of_agent_id
                                                           i)+
                                                         (Ckappa_sig.int_of_agent_id n) +1))
                          | Some j -> error, j
                        in
                        let error, join =
                          Cckappa_sig.join_mixture
                            parameters error (fun _ error i -> error,i)
                            f (get_bool r1) mixt
                        in
                        let error, dynamic, bool =
                          maybe_reachable static dynamic error join
                        in
                        let error =
                          if Remanent_parameters.get_trace parameters
                          then
                            let error =
                              let () =
                                Loggers.fprintf
                                  (Remanent_parameters.get_logger parameters)
                                  "FST:\n"
                              in

                              let error =
                                Print_cckappa.print_mixture parameters error
                                  handler (get_bool r1)
                              in
                              let () =
                                Loggers.fprintf
                                  (Remanent_parameters.get_logger parameters)
                                  "SND:\n"
                              in
                              let error =
                                Print_cckappa.print_mixture parameters error
                                  handler
                                  mixt
                              in
                              let () =
                                Loggers.fprintf
                                  (Remanent_parameters.get_logger parameters)
                                  "PUSHOUT:\n"
                              in
                              let error =
                                Print_cckappa.print_mixture parameters error handler join
                              in
                              let () =
                                if bool
                                then
                                  Loggers.fprintf
                                    (Remanent_parameters.get_logger parameters)
                                    "YES!!!\n"
                                else
                                  Loggers.fprintf
                                    (Remanent_parameters.get_logger parameters)
                                    "NO!!!\n"
                              in
                              let error =
                                Print_cckappa.print_mixture parameters error
                                  handler (get_bool r1)
                              in
                              let error =
                                Print_cckappa.print_mixture parameters error
                                  handler
                                  mixt
                              in
                              let error =
                                Print_cckappa.print_mixture parameters error handler join
                              in error
                            in error
                          else error in
                        (error, dynamic), bool)
                   couple
               in
               (error,dynamic),couple'
             with False (error) -> (error,dynamic),couple
             (* dynamic should be passed as well*)
           in
           if Quark_type.Labels.is_empty_couple couple'
           then  (error,dynamic),map'
           else (error,dynamic),
                Ckappa_sig.PairRule_setmap.Map.add
                  (a,b) couple' map'
         end
       with Pass error -> ((error,dynamic),map') (* dynamic should be passed as well*)
    )
    map
    ((error,dynamic),
     Ckappa_sig.PairRule_setmap.Map.empty
    )
