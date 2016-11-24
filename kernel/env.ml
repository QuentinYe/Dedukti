open Basics
open Term
open Rule
open Typing
open Signature

type env_error =
  | EnvErrorType of typing_error
  | EnvErrorSignature of signature_error
  | KindLevelDefinition of loc*ident

(* Wrapper around Signature *)

let sg = ref (Signature.make (hstring "noname"))

let init name = sg := Signature.make name

let get_name () = Signature.get_name !sg

let get_type l md id =
  try OK (Signature.get_type !sg l md id)
  with SignatureError e -> Err e

let get_dtree l md id =
  try OK (Signature.get_dtree !sg l md id)
  with SignatureError e -> Err e

let export () : bool = Signature.export !sg

let _declare_constant (l:loc) (id:ident) (ty:typ) : typ =
  let ty,sort = inference !sg ty in
  match sort with
    | Kind | Type _ -> Signature.add_declaration !sg l id ty ; ty
    | s -> raise (TypingError (SortExpected (ty,[],s)))

let _declare_definable (l:loc) (id:ident) (ty:typ) : typ =
  let ty,sort = inference !sg ty in
  match sort with
    | Kind | Type _ -> Signature.add_definable !sg l id ty ; ty
    | s -> raise (TypingError (SortExpected (ty,[],s)))

exception DefineExn of loc*ident

let _define (l:loc) (id:ident) (te:term) (ty_opt:typ option) : (term * typ) =
  let (te,ty) = match ty_opt with
    | None -> inference !sg te
    | Some ty -> checking !sg te ty
  in
  match ty with
  | Kind -> raise (DefineExn (l,id))
  | _ ->
    Signature.add_definable !sg l id ty;
    Signature.add_rules !sg [([],Pattern (l,get_name (),id,[]),te)];
    (te,ty)

let _define_op (l:loc) (id:ident) (te:term) (ty_opt:typ option) : (term * typ) =
  let (te,ty) = match ty_opt with
    | None -> inference !sg te
    | Some ty -> checking !sg te ty
  in
  match ty with
  | Kind -> raise (DefineExn (l,id))
  | _ -> Signature.add_declaration !sg l id ty; (te,ty)

let declare_constant l id ty : (typ,env_error) error =
  try OK ( _declare_constant l id ty )
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let declare_definable l id ty : (typ,env_error) error =
  try OK ( _declare_definable l id ty )
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let define l id te ty_opt : (term * typ,env_error) error =
  try OK ( _define l id te ty_opt )
  with
  | SignatureError e -> Err (EnvErrorSignature e)
  | TypingError e -> Err (EnvErrorType e)
  | DefineExn (l,id) -> Err (KindLevelDefinition (l,id))

let define_op l id te ty_opt : (term * typ,env_error) error =
  try OK ( _define_op l id te ty_opt )
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)
    | DefineExn (l,id) -> Err (KindLevelDefinition (l,id))

let add_rules (rules: rule list) : (rule2 list,env_error) error =
  try
    let rs2 = List.map (check_rule !sg) rules in
    Signature.add_rules !sg rs2;
    OK rs2
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let infer te =
  try  OK (inference !sg te)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let check te ty =
  try OK (ignore(checking !sg te ty))
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let whnf te =
  try
    let _ = inference !sg te in OK (Reduction.whnf !sg te)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let hnf te =
  try
    let _ = inference !sg te in OK (Reduction.hnf !sg te)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let snf te =
  try
    let _ = inference !sg te in OK (Reduction.snf !sg te)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let unsafe_snf te = Reduction.snf !sg te

let one te =
  try
    let _ = inference !sg te in OK (Reduction.one_step !sg te)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)

let are_convertible te1 te2 =
  try
    let _ = inference !sg te1 in
    let _ = inference !sg te2 in
      OK (Reduction.are_convertible !sg te1 te2)
  with
    | SignatureError e -> Err (EnvErrorSignature e)
    | TypingError e -> Err (EnvErrorType e)
