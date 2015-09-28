open Mods

module Edge = struct
  type t = ToFree
	 | Link of (int * int * int) (** sort * id * site *)

  let compare x y = match x,y with
    | ToFree, Link _ -> -2
    | Link _, ToFree -> 2
    | ToFree, ToFree -> 0
    | Link (_,n,s), Link (_,n',s') ->
       let c = int_compare n n' in
       if c <> 0 then c else int_compare s s'
end

type t = Edge.t Int2Map.t * int Int2Map.t * int IntMap.t
(** agent,site -> binding_state; agent,site -> internal_state; agent -> sort *)

let empty = (Int2Map.empty, Int2Map.empty, IntMap.empty)

let add_free ty ag s (connect,state,sort) =
  (Int2Map.add (ag,s) Edge.ToFree connect,state,
   (* !HACK! *) if s = 0 then IntMap.add ag ty sort else sort)
let add_internal ag s i (connect,state,sort) =
  (connect,Int2Map.add (ag,s) i state,sort)

let add_link ty ag s ty' ag' s' (connect,state,sort) =
  (Int2Map.add (ag,s) (Edge.Link (ty',ag',s'))
	       (Int2Map.add (ag',s') (Edge.Link (ty,ag,s)) connect),
   state,sort)

let remove ag s (connect,state,sort) = function
  | Edge.ToFree -> (Int2Map.remove (ag,s) connect,state,
		    (* !HACK! *) if s = 0 then IntMap.remove ag sort else sort)
  | Edge.Link (_,ag',s') ->
     (Int2Map.remove (ag,s) (Int2Map.remove (ag',s') connect),state,sort)
let remove_free ag s t = remove ag s t Edge.ToFree
let remove_internal ag s i (connect,state,sort) =
  (connect,Int2Map.remove (ag,s) state,sort)
let remove_link ag s ag' s' t = remove ag s t (Edge.Link (-1,ag',s'))

let is_free ag s (t,_,_) =
  try Int2Map.find (ag,s) t = Edge.ToFree with Not_found -> false
let is_internal i ag s (_,t,_) =
  try Int2Map.find (ag,s) t = i with Not_found -> false
let link_exists ag s ag' s' (t,_,_) =
  try match Int2Map.find (ag,s) t with
      | Edge.Link (_,ag'',s'') -> ag'=ag'' && s'=s''
      | Edge. ToFree -> false
  with Not_found -> false
let exists_fresh ag s ty s' (t,_,_) =
  try match Int2Map.find (ag,s) t with
      | Edge.Link (ty',ag',s'') ->
	 if ty'=ty && s'=s'' then Some ag' else None
      | Edge. ToFree -> None
  with Not_found -> None

(** The snapshot machinery *)
let one_connected_component sigs free_id node graph =
  let rec build acc free_id dangling (links,internals,sorts as graph) = function
    | [] -> acc,free_id,graph
    | node :: todos ->
       match IntMap.pop node sorts with
       | None, _ ->
	  failwith ("Node "^string_of_int node^" of graph has no entry in sorts")
       | Some ty, sorts' ->
	  let arity = Signature.arity sigs ty in
	  let ports = Array.make arity Raw_mixture.FREE in
	  let ints = Array.make arity None in
	  let (free_id',links',dangling',todos'),ports =
	    Tools.array_fold_left_mapi
	      (fun i (free_id,links,dangling,todos) _ ->
	       match Int2Map.pop (node,i) links with
	       | None, _ ->
		  failwith ("missing edge in graph for node "^string_of_int node
			    ^" edge "^string_of_int i)
	       | Some Edge.ToFree, links' ->
		  (free_id,links',dangling,todos),Raw_mixture.FREE
	       | Some (Edge.Link (_,n',s')), links' ->
		  match Int2Map.pop (n',s') dangling with
		  | None, dangling ->
		     (succ free_id,links',
		      Int2Map.add (node,i) free_id dangling,
		      if n' = node || List.mem n' todos then todos else n'::todos),
		     Raw_mixture.VAL free_id
		  | Some id, dangling' ->
		     (free_id,links',dangling',todos), Raw_mixture.VAL id)
	      (free_id,links,dangling,todos) ports in
	  let internals',ints =
	    Tools.array_fold_left_mapi
	      (fun i internals _ ->
	       let (a,b) = Int2Map.pop (node,i) internals in (b,a))
	      internals ints in
	  let skel =
	    { Raw_mixture.a_id = node; Raw_mixture.a_type = ty;
	      Raw_mixture.a_ports = ports; Raw_mixture.a_ints = ints; } in
	  build (skel::acc) free_id' dangling'
		(links',internals',sorts') todos'
  in build [] free_id Int2Map.empty graph [node]

let build_snapshot sigs graph =
  let rec increment x = function
    | [] -> [1,x]
    | (n,y as h)::t ->
       if Raw_mixture.equal x y then (succ n,y)::t
       else h::increment x t in
  let rec aux ccs free_id (_,_,sorts as graph) =
    match IntMap.root sorts with
    | None -> ccs
    | Some (node,_) ->
       let (out,free_id',graph') =
	 one_connected_component sigs free_id node graph in
       aux (increment out ccs) free_id' graph' in
  aux [] 1 graph

let print sigs f graph =
  Pp.list Pp.space (fun f (i,mix) ->
		    Format.fprintf f "%%init: %i @[<h>%a@]" i
				   (Raw_mixture.print sigs) mix)
	  f (build_snapshot sigs graph)

let debug_print f (links,ints,sorts) =
  Pp.set
    ~trailing:(fun f -> Format.fprintf f "@])")
    Int2Map.bindings (fun f -> Format.fprintf f ",")
    (fun f ((ag,s),l) ->
     let () =
       if s=0 then
	 let ty = try IntMap.find ag sorts with Not_found -> -42 in
	 let () = if ag <> 1 then Format.fprintf f "@])%t" Pp.space in
	 Format.fprintf f "%i:%i(@[" ag ty in
     Format.fprintf
       f "%i%t%t" s
       (try let int = Int2Map.find (ag,s) ints in
	    fun f -> Format.fprintf f "~%i" int
	with Not_found -> fun _ -> ())
       (match l with
	| Edge.ToFree -> fun _ -> ()
	| Edge.Link (ty',ag',s') ->
	   fun f -> Format.fprintf f "->%i:%i.%i" ag' ty' s'))
    f links

type path = (int * int * int * int) list
let is_valid_path graph l =
  List.for_all (fun (a,s,a',s') -> link_exists a s a' s' graph) l

let pathes_of_interrest stop_on_find is_interresting (links,_,_) origin =
  let rec infinite_search (id,path as x) site (stop,don,out,next as acc) =
    try
      match Int2Map.find (id,site) links with
      | Edge.ToFree  -> infinite_search x (succ site) acc
      | Edge.Link (_,id',site') ->
	 if (stop&&stop_on_find)||IntSet.mem id' don
	 then infinite_search x (succ site) acc
	 else
	   let don' = IntSet.add id' don in
	   let path' = (id,site,site',id')::path in
	   let store = is_interresting id' in
	   let out' = if store then (id',path')::out else out in
	   let next' = (id',path')::next in
	   infinite_search x (succ site) (stop||store,don',out',next')
    with Not_found -> acc in
  let rec traversal don out next = function
    | x::todos ->
       let stop,don',out',next' = infinite_search x 0 (false,don,out,next) in
       if stop&&stop_on_find then out else traversal don' out' next' todos
    | [] -> match next with [] -> out | _ -> traversal don out [] next
  in traversal IntSet.empty [] [] [origin,[]]

let are_connected ?candidate graph x y =
  match candidate with
  | Some p when is_valid_path graph p -> Some p
  | (Some _ | None) ->
     match pathes_of_interrest true (fun z -> z = y) graph x with
     | [] -> None
     | [ _,p ] -> Some p
     | _ :: _ -> failwith "Edges.are_they_connected completely broken"
