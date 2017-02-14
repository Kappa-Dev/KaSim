(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type t = {
  mutable alg_var_overwrite   : (string * Nbr.t) list;
  mutable minValue            : float option;
  mutable maxValue            : float option;
  mutable plotPeriod          : float option;
  mutable rescale             : float option;
  mutable marshalizedInFile   : string;
  mutable inputKappaFileNames : string list;
  mutable outputDataFile      : string option;
  mutable outputDirectory     : string;
  mutable batchmode           : bool;
  mutable interactive         : bool;
}

let default : t = {
  alg_var_overwrite = [];
  minValue = None ;
  maxValue = None;
  plotPeriod = None;
  rescale = None;
  marshalizedInFile = "";
  inputKappaFileNames = [];
  outputDataFile = None;
  outputDirectory = ".";
  batchmode  = false;
  interactive = false;
}

let options (t :t)  : (string * Arg.spec * string) list = [
  ("-i",
   Arg.String (fun fic ->
       t.inputKappaFileNames <- fic::t.inputKappaFileNames),
   "name of a kappa file to use as input (can be used multiple times for multiple input files)");
  ("-initial",
   Arg.Float (fun time -> t.minValue <- Some time),
   "Min time of simulation (arbitrary time unit)");
  ("-l",
   Arg.Float(fun time -> t.maxValue <- Some time),
   "Limit of the simulation");
  ("-t",
   Arg.Float (fun f ->
       raise (Arg.Bad ("Option '-t' has been replace by '[-u time] -l "^
                       string_of_float f^"'"))),"Deprecated option");
  ("-p",
   Arg.Float(fun pointNumberValue -> t.plotPeriod <- Some pointNumberValue),
   "plot period: time interval between points in plot (default: 1.0)");
  ("-var",
   Arg.Tuple
     (let tmp_var_name = ref "" in
      [Arg.String (fun name -> tmp_var_name := name);
       Arg.String (fun var_val ->
           t.alg_var_overwrite <-
             (!tmp_var_name,
              try Nbr.of_string var_val with
                Failure _ ->
                raise (Arg.Bad ("\""^var_val^"\" is not a valid value")))
             ::t.alg_var_overwrite)]),
   "Set a variable to a given value");
  ("-o", Arg.String
     (fun outputDataFile -> t.outputDataFile <- Some outputDataFile),
   "file name for data output") ;
  ("-d",
   Arg.String (fun outputDirectory -> t.outputDirectory <- outputDirectory),
   "Specifies directory name where output file(s) should be stored") ;
  ("-load-sim",
   Arg.String (fun file -> t.marshalizedInFile <- file),
   "load simulation package instead of kappa files") ;
  ("-mode",
   Arg.String
     (fun m -> if m = "batch" then t.batchmode <- true
       else if m = "interactive" then t.interactive <- true),
   "either \"batch\" to never ask anything to the user or \"interactive\" to ask something before doing anything") ;
  ("-rescale", Arg.Float (fun i -> t.rescale <- Some i),
   "Apply rescaling factor to initial condition")
]
