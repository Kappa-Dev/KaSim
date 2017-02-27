(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

module Html = Tyxml_js.Html5
module R = Tyxml_js.R
open Lwt.Infix

module ButtonPerturbation : Ui_common.Div = struct
  let id = "panel_settings_perturbation_button"
  let button =
    Html.button
      ~a:[ Html.a_id id
         ; Html.Unsafe.string_attrib "type" "button"
         ; Html.a_class ["btn" ; "btn-default" ; ] ]
      [ Html.cdata "perturbation" ]
  let content () : [> Html_types.div ] Tyxml_js.Html.elt list =
    [ Html.div [ button ] ]

  let run_perturbation () : unit = Panel_settings_controller.perturb_simulation ()

  let onload () : unit =
    let button_dom = Tyxml_js.To_dom.of_button button in
    let handler = (fun _ -> let () = run_perturbation () in Js._true) in
    let () = button_dom##.onclick := Dom.handler handler in
    ()
end

module InputPerturbation : Ui_common.Div = struct
  let id = "panel_settings_perturbation_code"
  let input =
    Html.input
      ~a:[Html.a_id id;
          Html.a_input_type `Text;
          Html.a_class ["form-control"];
          Html.a_placeholder "Simulation Perturbation";]
      ()

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list =
    [ Html.div [ input ] ]
   let onload () : unit =
     let input_dom = Tyxml_js.To_dom.of_input input in
     let handler =
             (fun (event : Dom_html.event Js.t)  ->
                let target : Dom_html.element Js.t =
                  Js.Opt.get
                    event##.target
                    (fun () ->
                   Common.toss
                     "Panel_settings.InputPerturbation.onload input")
                in
                let input : Dom_html.inputElement Js.t = Js.Unsafe.coerce target in
                let model_perturbation : string = Js.to_string input##.value in
                let () = State_perturbation.set_model_perturbation model_perturbation in
                Js._true)
     in
     let () = input_dom##.onchange := Dom.handler handler in
     ()

end

let signal_change input_dom signal_handler =
  input_dom##.onchange :=
    Dom_html.handler
      (fun _ -> let () = signal_handler (Js.to_string (input_dom##.value)) in
        Js._true)

module InputPauseCondition : Ui_common.Div = struct
  let id = "panel_settings_pause_condition"
  let input =
    Html.input
      ~a:[Html.a_id id ;
        Html.a_input_type `Text;
          Html.a_class ["form-control"];
          Html.a_placeholder "[T] > 100" ;
          Tyxml_js.R.Html.a_value State_parameter.model_pause_condition ]
    ()
  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [input]

  let dom = Tyxml_js.To_dom.of_input input

  let onload () =
    let () = signal_change dom
        (fun value ->
           let v' = if value = "" then "[false]" else value in
           State_parameter.set_model_pause_condition v') in
    ()
end

module InputPlotPeriod : Ui_common.Div = struct
  let id = "panel_settings_plot_period"
let format_float_string value =
  let n = string_of_float value in
  let length = String.length n in
  if length > 0 && String.get n (length - 1) = '.' then
    n^"0"
  else
    n

let input =
  Html.input
    ~a:[Html.a_input_type `Number;
        Html.a_id id;
        Html.a_class [ "form-control"];
        Html.a_placeholder "time units";
        Html.Unsafe.string_attrib "min" (string_of_float epsilon_float);
        Tyxml_js.R.Html.a_value
          (React.S.l1 format_float_string State_parameter.model_plot_period)]
    ()
  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [input]

  let onload () =
    let input_dom = Tyxml_js.To_dom.of_input input in
    let () = signal_change input_dom
        (fun value ->
           let old_value = React.S.value State_parameter.model_plot_period in
           let reset_value () = input_dom##.value := Js.string (string_of_float old_value) in
           try
             let new_value = (float_of_string value) in
             if new_value > 0.0 then
               State_parameter.set_model_plot_period new_value
             else
               reset_value ()
         with | Not_found | Failure _ -> reset_value ()) in
    ()

end

module ButtonConfiguration : Ui_common.Div = struct
  let configuration_seed_input_id = "configuration_input"
  let configuration_seed_input =
    Html.input ~a:[ Html.a_id configuration_seed_input_id ;
                    Html.a_input_type `Number;
                    Html.a_class ["form-control"];
                  ] ()
  let configuration_save_button_id = "configuration_save_button"
  let configuration_save_button =
    Html.button
      ~a:[ Html.a_class [ "btn" ; "btn-default" ] ;
           Html.a_id configuration_save_button_id ;
         ]
      [ Html.cdata "Save" ]
  let simulation_configuration_modal_id = "simulation_configuration_modal"
  let configuration_modal = Ui_common.create_modal
      ~id:simulation_configuration_modal_id
      ~title_label:"Simulation Configuration"
      ~buttons:[ configuration_save_button ]
      ~body:[[%html
              {|<div class="row">
                   <div class="col-md-1"><label for={[configuration_seed_input_id]}>Seed</label></div>
                   <div class="col-md-5">|}
                     [configuration_seed_input]{|</div>
                </div>|}] ; ]

  let id = "configuration_button"
  let configuration_button =
    Html.button
      ~a:[ Html.a_class [ "btn" ; "btn-default" ] ;
           Html.a_id id ;
         ]
      [ Html.cdata "Options" ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list =
    [configuration_button; configuration_modal]
  let onload () =
    let () = Common.jquery_on
      (Format.sprintf "#%s" configuration_save_button_id)
      ("click")
      (Dom_html.handler
         (fun (_ : Dom_html.event Js.t)  ->
            let input : Dom_html.inputElement Js.t = Tyxml_js.To_dom.of_input configuration_seed_input in
            let value : string = Js.to_string input##.value in
            let model_seed = try Some (int_of_string value) with Failure _ -> None in
            let () = State_parameter.set_model_seed model_seed in
            let () =
              Common.modal
                ~id:("#"^simulation_configuration_modal_id)
                ~action:"hide"
            in

            Js._true))
    in
    let () = Common.jquery_on
      ("#"^id)
      ("click")
      (Dom_html.handler
         (fun (_ : Dom_html.event Js.t)  ->
            let input : Dom_html.inputElement Js.t = Tyxml_js.To_dom.of_input configuration_seed_input in
            let () = input##.value := Js.string
                  (match React.S.value State_parameter.model_seed with
                   | None -> ""
                   | Some model_seed -> string_of_int model_seed) in
            let () =
              Common.modal
                ~id:("#"^simulation_configuration_modal_id)
                ~action:"show"
            in
            Js._false)) in
    ()
end

module DivErrorMessage : Ui_common.Div = struct
  let id = "configuration_error_div"
  (* TODO : [%html {|<div class="alert-sm alert alert-danger"> « 1/2 » [abc.ka] Malformed agent 'adfsa' </div>|}] *)
  let message_label (message : Api_types_j.message) (index : int) (length : int) : string =
    (Format.sprintf  "%d/%d %s %s" index length
       (match message.Api_types_j.message_range with
        | None -> ""
        | Some range -> Format.sprintf "[ %s ]" range.Api_types_j.file)
       message.Api_types_j.message_text)
  let alert_messages =
  Html.div
    ~a:[Html.a_id id;
        Tyxml_js.R.Html.a_class
          (React.S.bind
             State_error.errors
             (fun error ->
                React.S.const
                  (match error with
                   | None -> [ "alert-sm" ; "alert" ; ]
                   | Some _ -> [ "alert-sm" ; "alert" ; "alert-danger" ; ]
                  )
             )
          );
       ]
    [Tyxml_js.R.Html.pcdata
       (React.S.bind
          State_error.errors
          (fun error ->
             React.S.const
               (match error with
                | None -> ""
                | Some errors ->
                  (match errors with
                   | [] -> ""
                   | h::_ -> message_label h 1 (List.length errors))
               )
          )
       )
    ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [ alert_messages ]

  let onload () = ()
end

module ButtonStart : Ui_common.Div = struct
  let id = "panel_settings_start_button"
  let button =
    Html.button
      ~a:([ Html.a_id id ;
            Html.Unsafe.string_attrib "type" "button" ;
            Html.a_class [ "btn" ;
                           "btn-default" ; ] ; ])
      [ Html.cdata "start" ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [button]

  let onload () =
    let start_button_dom = Tyxml_js.To_dom.of_button button in
    let () = start_button_dom##.onclick :=
        Dom.handler
          (fun _ ->
             let () = Panel_settings_controller.start_simulation () in
             Js._true)
    in

    ()
end

module ButtonClear : Ui_common.Div = struct
  let id = "panel_settings_clear_button"
  let button =
  Html.button
    ~a:[ Html.a_id id
       ; Html.Unsafe.string_attrib "type" "button"
       ; Html.a_class ["btn" ;
                       "btn-default" ; ] ]
    [ Html.cdata "clear" ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [button]

  let onload () =
    let dom = Tyxml_js.To_dom.of_button button in
    let () = dom##.onclick :=
      Dom.handler
        (fun _ ->
           let () = Panel_settings_controller.stop_simulation () in
           Js._true)
    in
    ()

end

module ButtonPause : Ui_common.Div = struct
  let id = "panel_settings_pause_button"
  let button =
  Html.button
    ~a:[ Html.a_id id
       ; Html.Unsafe.string_attrib "type" "button"
       ; Html.a_class ["btn" ;
                       "btn-default" ; ] ]
    [ Html.cdata "pause" ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [button]

  let onload () =
    let button_dom = Tyxml_js.To_dom.of_button button in
    let () = button_dom##.onclick :=
      Dom.handler
        (fun _ ->
           let () = Panel_settings_controller.pause_simulation () in
           Js._true)
  in
    ()

end

module ButtonContinue : Ui_common.Div = struct
  let id = "panel_settings_continue_button"
  let button =
  Html.button
    ~a:[ Html.a_id id
       ; Html.Unsafe.string_attrib "type" "button"
       ; Html.a_class ["btn" ;
                       "btn-default" ; ] ]
    [ Html.cdata "continue" ]

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [button]

  let onload () =
    let button_dom = Tyxml_js.To_dom.of_button button in
    let () = button_dom##.onclick :=
        Dom.handler
          (fun _ ->
             let () = Panel_settings_controller.continue_simulation () in
             Js._true)
    in
    ()

end

module SelectRuntime : Ui_common.Div = struct

let id ="settings_select_runtime"
  let select_options, select_options_handle = ReactiveData.RList.create []
  let select =
    Tyxml_js.R.Html.select
      ~a:[Html.a_id id]
      select_options

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list = [select]

  let onload () =
    let _ =
      React.S.bind
        State_runtime.model
        (fun model ->
           let options =
             let current_id =
               State_runtime.spec_id  model.State_runtime.model_current in
             List.map
               (fun spec ->
                  let spec_id = State_runtime.spec_id spec in
                  let selected =
                    if current_id = spec_id  then
                      [Html.a_selected () ;]
                    else [] in
                  Html.option
                      ~a:([Html.a_value spec_id ;
                         ]@ selected)
                      (Html.pcdata spec_id)
               )
               model.State_runtime.model_runtimes in
           let () = ReactiveData.RList.set select_options_handle options in
           React.S.const ())
    in
    let select_dom = Tyxml_js.To_dom.of_select select in
    let () = select_dom##.onchange :=
        Dom.handler
          (fun _ ->
             let () =
               Common.async
                 (fun () ->
                    (State_runtime.set_manager (Js.to_string select_dom##.value)) >>=
                    (fun _ -> Lwt.return_unit)
                 ) in
             Js._true
          )
    in

    ()

end

module DivStatusIndicator : Ui_common.Div = struct
  let id = "setting_status_indicator"
  let content () : [> Html_types.div ] Tyxml_js.Html.elt list =
    let debug =
      Html.div
        [ Tyxml_js.R.Html.pcdata
            (React.S.bind
               State_simulation.model
               (fun model ->
                  let option =
                    Utility.option_map
                      State_simulation.model_state_to_string
                      (State_simulation.model_simulation_state
                     model.State_simulation.model_current)
                  in
                  let label = match option with None -> "None" | Some l -> l in
                  React.S.const label
               )
            );
          Tyxml_js.R.Html.pcdata
            (React.S.bind
               State_simulation.model
               (function model ->
                React.S.const
                  (match model.State_simulation.model_current with
                   | None -> "None"
                   | Some _ -> "Some"
                  )
               )
            )
        ]
    in
    [ Html.div
        ~a:[ Html.a_id id ]
        (Ui_common.level ~debug ()) ]

  let onload () = ()
end

module RunningPanelLayout : Ui_common.Div = struct
  let id = "settings_runetime_layout"
  let lift f x = match x with | None -> None | Some x -> f x
  let progress_bar
      (percent_signal : int Tyxml_js.R.Html.wrap)
      (value_signal : string React.signal) =
    Html.div
      ~a:[ Html.Unsafe.string_attrib "role" "progressbar" ;
           Tyxml_js.R.Html.Unsafe.int_attrib "aria-valuenow" percent_signal ;
           Html.Unsafe.int_attrib "aria-valuemin" 0 ;
           Html.Unsafe.int_attrib "aria-valuemax" 100 ;
           Tyxml_js.R.Html.Unsafe.string_attrib
           "style"
           (React.S.map
              (fun s -> Format.sprintf "width: %d%%;" s)
              percent_signal) ;
           Html.a_class ["progress-bar"] ]
    [ Tyxml_js.R.Html.pcdata
        (React.S.bind
           value_signal
           (fun value -> React.S.const value)
        )
    ]

  let time_progress_bar  () =
    progress_bar
      (React.S.map
         (fun model ->
            let simulation_info = State_simulation.model_simulation_info model in
            let time_percent : int option =
              lift
                (fun (status : Api_types_j.simulation_info) ->
                   status.Api_types_j.simulation_info_progress.Api_types_j.simulation_progress_time_percentage )
                simulation_info
            in
            let time_percent : int = Tools.unsome 100 time_percent in
            time_percent
         )
         State_simulation.model)
      (React.S.map (fun model ->
           let simulation_info = State_simulation.model_simulation_info model in
           let time : float option =
             lift (fun (status : Api_types_j.simulation_info) ->
                 Some status.Api_types_j.simulation_info_progress.Api_types_j.simulation_progress_time) simulation_info in
           let time : float = Tools.unsome 0.0 time in
           string_of_float time
         )
          State_simulation.model)


  let event_progress_bar () =
    progress_bar
      (React.S.map (fun model ->
           let simulation_info = State_simulation.model_simulation_info model in
           let event_percentage : int option =
             lift (fun (status : Api_types_j.simulation_info) ->
                 status.Api_types_j.simulation_info_progress.Api_types_j.simulation_progress_event_percentage) simulation_info in
           let event_percentage : int = Tools.unsome 100 event_percentage in
           event_percentage
         )
          State_simulation.model)
      (React.S.map (fun model ->
           let simulation_info = State_simulation.model_simulation_info model in
           let event : int option =
             lift (fun (status : Api_types_j.simulation_info) ->
                 Some status.Api_types_j.simulation_info_progress.Api_types_j.simulation_progress_event)
               simulation_info
           in
           let event : int = Tools.unsome 0 event in
           string_of_int event
         )
          State_simulation.model)

  let tracked_events state =
    let tracked_events : int option =
      lift (fun (status : Api_types_j.simulation_info) ->
        status.Api_types_j.simulation_info_progress.Api_types_j.simulation_progress_tracked_events)
        state
    in
    match tracked_events with
      None -> None
  | Some tracked_events ->
    if tracked_events > 0 then
      Some tracked_events
    else
      None

  let tracked_events_count () =
    Tyxml_js.R.Html.pcdata
      (React.S.map
         (fun model ->
            let simulation_info = State_simulation.model_simulation_info model in
            match tracked_events simulation_info with
            | Some tracked_events -> string_of_int tracked_events
            | None -> " "
         )
         State_simulation.model)

  let tracked_events_label () =
    Tyxml_js.R.Html.pcdata
      (React.S.map
         (fun model ->
            let simulation_info = State_simulation.model_simulation_info model in
            match tracked_events simulation_info with
              Some _ -> "tracked events"
            | None -> " "
         )
         State_simulation.model)

  let content () : [> Html_types.div ] Tyxml_js.Html.elt list =
    [ [%html {|
     <div class="row" id="|}id{|">
        <div class="col-md-4 col-xs-10">
            <div class="progress">
            |}[ event_progress_bar () ]{|
            </div>
        </div>
        <div class="col-md-2 col-xs-2">events</div>
     </div>|}] ;
     [%html {|
     <div class="row">
        <div class="col-md-4 col-xs-10">
            <div class="progress">
            |}[ time_progress_bar () ]{|
            </div>
        </div>
        <div class="col-md-2 col-xs-2">time</div>
     </div>|}] ;
     [%html {|
     <div class="row">
        <div class="col-md-4 col-xs-10">
           |}[ tracked_events_count () ]{|
        </div>
        <div class="col-md-2 col-xs-2">
           |}[ tracked_events_label () ]{|
        </div>
     </div>
   |}] ; ]

  let onload () = ()

end

let hidden_class = "hidden"
let visible_class = "visible"

let visible_on_states
    ?(a_class=[])
    (state : State_simulation.model_state list) : string list React.signal =
  let hidden_class = ["hidden"] in
  let visible_class = ["visible"] in
  React.S.bind
    State_simulation.model
    (fun model ->
       let current_state = State_simulation.model_simulation_state model.State_simulation.model_current in
       React.S.const
         (match current_state with
          | None -> a_class@hidden_class
          | Some current_state ->
            if List.mem current_state state then
              a_class@visible_class
            else
              a_class@hidden_class))

let stopped_body () : [> Html_types.div ] Tyxml_js.Html5.elt =
  let stopped_row =
    Html.div
      ~a:[ Tyxml_js.R.Html.a_class
             (visible_on_states
                ~a_class:[ "form-group"; "form-group-sm" ]
                [ State_simulation.STOPPED ; ]) ]
    [%html {|
            <label class="col-lg-1 col-md-2 col-xs-2 control-label" for="|}InputPlotPeriod.id{|">Plot period</label>
            <div class="col-md-2 col-xs-3">|}(InputPlotPeriod.content ()){|</div>
            <div class="col-xs-6 col-md-3">|}
        (ButtonConfiguration.content ()){|</div>|}] in
    let paused_row =
      Html.div
      ~a:[ Tyxml_js.R.Html.a_class
             (visible_on_states
                ~a_class:[ "form-group" ]
                [ State_simulation.PAUSED ; ]) ]
      [ Html.div ~a:[ Html.a_class ["col-md-10"; "col-xs-9" ] ] (InputPerturbation.content ()) ;
        Html.div ~a:[ Html.a_class ["col-md-2"; "col-xs-3" ] ] (ButtonPerturbation.content ()) ]
    in
    Html.div
      ~a:[ Tyxml_js.R.Html.a_class
             (visible_on_states
                ~a_class:[ "panel-body" ; "panel-controls" ]
                [ State_simulation.STOPPED ;
                  State_simulation.PAUSED ;]) ]
      [[%html {|
         <form class="form-horizontal">
          <div class="form-group">
            <label class="col-lg-1 col-sm-2 hidden-xs control-label" for="|}InputPauseCondition.id{|">Pause if</label>
            <div class="col-md-2 col-sm-3 col-xs-5">|}(InputPauseCondition.content ()){|</div>
            <div class="col-lg-9 col-md-8 col-xs-7">|}(DivErrorMessage.content ()){|</div>
          </div>
                                                                       |}
          [paused_row;stopped_row]
          {|</form>|}]]

  let initializing_body () : [> Html_types.div ] Tyxml_js.Html5.elt =
    Html.div
      ~a:[ Tyxml_js.R.Html.a_class
             (visible_on_states
                ~a_class:[ "panel-body" ; "panel-controls" ]
                [ State_simulation.INITALIZING ; ]) ]
      [ Html.entity "nbsp" ]

  let running_body () =
    Html.div
      ~a:[ Tyxml_js.R.Html.a_class
             (visible_on_states
                ~a_class:[ "panel-body" ; "panel-controls" ]
                [ State_simulation.RUNNING ; ]) ]
      (RunningPanelLayout.content ())
let footer () =
  [%html {|
         <div class="panel-footer">
            <div class="row">
         |}[ Html.div
               ~a:[ Tyxml_js.R.Html.a_class
                    (visible_on_states
                    ~a_class:[ "col-md-2"; "col-xs-4" ]
                     [ State_simulation.STOPPED ; ]) ]
               (ButtonStart.content ());
             Html.div
               ~a:[ Tyxml_js.R.Html.a_class
                    (visible_on_states
                    ~a_class:[ "col-md-2"; "col-xs-4" ]
                     [ State_simulation.PAUSED ; ]) ]
               (ButtonContinue.content ());
             Html.div
               ~a:[ Tyxml_js.R.Html.a_class
                    (visible_on_states
                    ~a_class:[ "col-md-2"; "col-xs-4" ]
                     [ State_simulation.RUNNING ; ]) ]
               (ButtonPause.content ());
             Html.div
               ~a:[ Tyxml_js.R.Html.a_class
                    (visible_on_states
                    ~a_class:[ "col-md-2"; "col-xs-3" ]
                    [ State_simulation.PAUSED ;
                      State_simulation.RUNNING ; ]) ]
               (ButtonClear.content ());
             Html.div
               ~a:[ Html.a_class [ "col-md-1"; "col-xs-5" ] ]
               ((DivStatusIndicator.content ())
                @
                [ Html.entity "nbsp" ; ]) ]{|
            </div>
         </div>
  |}]
let content () =
  [[%html {|
      <div class="panel panel-default">
         |}[stopped_body ()]{|
         |}[initializing_body ()]{|
         |}[running_body ()]{|
         |}[footer ()]{|
     </div>
  |}]]

let onload () : unit =
  let () = ButtonPerturbation.onload () in
  let () = InputPerturbation.onload () in
  let () = InputPauseCondition.onload () in
  let () = InputPlotPeriod.onload () in
  let () = ButtonConfiguration.onload () in
  let () = DivErrorMessage.onload () in
  let () = ButtonStart.onload () in
  let () = ButtonPause.onload () in
  let () = ButtonContinue.onload () in
  let () = ButtonClear.onload () in
  let () = SelectRuntime.onload () in
  let () = DivStatusIndicator.onload() in
  ()
let onresize () : unit = ()