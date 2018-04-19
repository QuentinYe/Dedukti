open Basic
open Term
open Rule
open Parser
open Entry

type path = string

module MDepSet = Set.Make(struct type t = Basic.mident * path let compare = compare end)

module NameSet = Set.Make(struct type t = Basic.name let compare = compare end)

type ideps = {up: NameSet.t ; down: NameSet.t}

type deps =
  {
    file:path; (** path associated to the module *)
    deps: MDepSet.t; (** pairs of module and its associated path *)
    ideps: (ident, ideps) Hashtbl.t;
  }

type t = (mident, deps) Hashtbl.t

let deps : t = Hashtbl.create 81

(*
let update_up item up =
  if Hashtbl.mem deps item then
    let dep = Hashtbl.find deps item in
    Hashtbl.replace deps item {dep with up=NameSet.add up dep.up}
  else
    Hashtbl.add deps item {up=NameSet.singleton up;down=NameSet.empty}

let update_down item down =
  if Hashtbl.mem deps item then
    let dep = Hashtbl.find deps item in
    Hashtbl.replace deps item {dep with down=NameSet.add down dep.down}
  else
    Hashtbl.add deps item {down=NameSet.singleton down;up=NameSet.empty}

let update_deps item dep =
  update_down item dep;
  update_up dep item
*)

let empty_deps () = {file=""; deps = MDepSet.empty; ideps=Hashtbl.create 81}

(** [deps] contains the dependencies found so far, reset before each file. *)
let current_mod  : mident    ref = ref (mk_mident "<not initialised>")
let current_deps : deps      ref = ref (empty_deps ())
let ignore       : bool      ref = ref false


let in_deps : mident -> bool = fun n ->
  MDepSet.exists (fun (md,_) -> mident_eq md n) !current_deps.deps

let add_mdep : mident -> path option -> unit = fun name file ->
  match file with
  | None -> ()
  | Some file ->
    current_deps := {!current_deps with deps = MDepSet.add (name, file) !current_deps.deps}

(** [find_dk md path] looks for the ".dk" file corresponding to the module
    named [name] in the directories of [path]. If no corresponding file is
    found, or if there are several possibilities, the program fails with a
    graceful error message. *)
let find_dk : mident -> path list -> path option = fun md path ->
  let name = string_of_mident md in
  let file_name = name ^ ".dk" in
  let path = Filename.current_dir_name :: path in
  let path = List.sort_uniq String.compare path in
  let add_dir dir =
    if dir = Filename.current_dir_name then file_name
    else Filename.concat dir file_name
  in
  let files = List.map add_dir path in
  match List.filter Sys.file_exists files with
  | []  ->
    if !ignore then None
    else (Printf.eprintf "No file for module %S in path...\n%!" name; exit 1)
  | [f] -> Some f
  | fs  -> Printf.eprintf "Several files correspond to module %S...\n" name;
           List.iter (Printf.eprintf "  - %s\n%!") fs; exit 1

(** [add_dep name] adds the module named [name] to the list of dependencies if
    no corresponding ".dko" file is found in the load path. The dependency is
    not added either if it is already present. *)
let add_dep : mident -> unit = fun md ->
  if md = !current_mod || in_deps md then () else
    add_mdep md (find_dk md (get_path ()))

(** Term / pattern / entry traversal commands. *)

let mk_name c =
  add_dep (md c)

let rec mk_term t =
  match t with
  | Kind | Type _ | DB _ -> ()
  | Const(_,c)           -> mk_name c
  | App(f,a,args)        -> List.iter mk_term (f::a::args)
  | Lam(_,_,None,te)     -> mk_term te
  | Lam(_,_,Some(ty),te) -> mk_term ty; mk_term te
  | Pi (_,_,a,b)         -> mk_term a; mk_term b

let rec mk_pattern p =
  match p with
  | Var(_,_,_,args)   -> List.iter mk_pattern args
  | Pattern(_,c,args) -> mk_name c; List.iter mk_pattern args
  | Lambda(_,_,te)    -> mk_pattern te
  | Brackets(t)       -> mk_term t

let mk_rule r =
  mk_pattern r.pat; mk_term r.rhs

let handle_entry e =
  match e with
  | Decl(_,_,_,te)              -> mk_term te
  | Def(_,_,_,None,te)          -> mk_term te
  | Def(_,_,_,Some(ty),te)      -> mk_term ty; mk_term te
  | Rules(rs)                   -> List.iter mk_rule rs
  | Eval(_,_,te)                -> mk_term te
  | Infer (_,_,te)              -> mk_term te
  | Check(_,_,_,Convert(t1,t2)) -> mk_term t1; mk_term t2
  | Check(_,_,_,HasType(te,ty)) -> mk_term te; mk_term ty
  | DTree(_,_,_)                -> ()
  | Print(_,_)                  -> ()
  | Name(_,_)                   -> ()
  | Require(_,md)               -> add_dep md

let handle_file : string -> unit = fun file ->
  try
    (* Initialisation. *)
    let md = Basic.mk_mident file in
    current_mod := md;
    current_deps := empty_deps ();
    current_deps := {!current_deps with file};
    (* Actully parsing and gathering data. *)
    let input = open_in file in
    Parser.handle_channel md handle_entry input;
    close_in input;
    Hashtbl.add deps md !current_deps
  with
  | Parse_error(loc,msg)      -> Printf.eprintf "Parse error...\n%!"; exit 1
  | Sys_error err             -> Printf.eprintf "ERROR %s.\n%!" err; exit 1
  | Exit                      -> exit 3

(** Output main program. *)

let output_deps : out_channel -> t -> unit = fun oc data ->
  let objfile src = Filename.chop_extension src ^ ".dko" in
  let output_line : mident -> deps -> unit = fun _ deps ->
    let file = deps.file in
    let deps = List.map (fun (_,src) -> objfile src) (MDepSet.elements deps.deps) in
    let deps = String.concat " " deps in
    Printf.fprintf oc "%s : %s %s\n" (objfile file) file deps
  in
  Hashtbl.iter output_line data

let topological_sort graph =
  let rec explore path visited node =
    if List.mem node path then
      begin
        Printf.eprintf "Dependecies are circular...";
        exit 1
      end;
    if List.mem node visited then visited else
      let edges = try List.assoc node graph with Not_found ->
        if !ignore then
          []
        else
         (Printf.eprintf "Cannot compute dependencies for the file %S... (maybe you forgot to put it on the command line?)\n%!" node; exit 1)
      in
      node :: List.fold_left (explore (node :: path)) visited (List.map snd edges)
  in
  List.fold_left (fun visited (n,_) -> explore [] visited n) [] graph

let output_sorted : out_channel -> t -> unit = fun oc data ->
  let to_graph _ deps graph =
    (deps.file, MDepSet.elements deps.deps)::graph
  in
  let deps = Hashtbl.fold to_graph data [] in
  let deps = List.rev (topological_sort deps) in
  Printf.printf "%s\n" (String.concat " " deps)

let _ =
  (* Parsing of command line arguments. *)
  let output  = ref stdout in
  let sorted  = ref false  in
  let args = Arg.align
    [ ( "-o"
      , Arg.String (fun n -> output := open_out n)
      , "FILE Outputs to file FILE" )
    ; ( "-s"
      , Arg.Set sorted
      , " Sort the source files according to their dependencies" )
    ; ( "--ignore"
      , Arg.Set ignore
      , " If some dependencies are not found, ignore them" )
    ; ( "-I"
      , Arg.String Basic.add_path
      , "DIR Add the directory DIR to the load path" ) ]
  in
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [OPTION]... [FILE]...\n" in
  let usage = usage ^ "Available options:" in
  let files =
    let files = ref [] in
    Arg.parse args (fun f -> files := f :: !files) usage;
    List.rev !files
  in
  (* Actual work. *)
  List.iter handle_file files;
  let output_fun = if !sorted then output_sorted else output_deps in
  output_fun !output deps;
  close_out !output
