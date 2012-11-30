open Types

exception IncorrectFileName

(* Arguments *)

let args = [
        ("-o", Arg.String (fun s -> Global.out   := (open_out s)  )     , "output file"         ) ;
        ("-c", Arg.Set Global.do_not_check                              , "do not check"        ) ;
        ("-q", Arg.Set Global.quiet                                     , "quiet"               ) ;
        ("-l", Arg.String (fun s -> Global.libs := s::(!Global.libs))   , "load a library"      ) ;
        ("-r", Arg.Set Global.ignore_redefinition                       , "ignore redefinition" ) ;
        ("-g", Arg.Set Global.generate_lua_file                         , "generate a lua file" )
]

let set_name str =
  let bname = Filename.basename str in
  let name  =
    try Filename.chop_extension bname
    with Invalid_argument _ -> bname
  in 
    if Str.string_match (Str.regexp "[a-zA-Z_][a-zA-Z_0-9]*") name 0 then
      Global.name := name
    else
      raise IncorrectFileName (*FIXME*)

(* Error Msgs *)

let error str = prerr_string str ; prerr_newline () ; exit 1 

(* Parsing *)

let parse lb = 
  try
      while true do Parser.top Lexer.token lb done
  with 
    | Parsing.Parse_error       -> 
        begin
          let curr = lb.Lexing.lex_curr_p in
          let line = curr.Lexing.pos_lnum in
          let cnum = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in
          let tok = Lexing.lexeme lb in
            raise (ParsingError (ParserError (tok,(line,cnum))))
        end

(* Main *)

let main str =
  try
    if !Global.quiet then () else print_endline (" --- Processing " ^ str ^ " --- ");
    let file = open_in str      in
    let _ = set_name str        in
    let lexbuf = Lexing.from_channel file in
      (if !Global.generate_lua_file || !Global.do_not_check then LuaCodeGeneration2.prelude ()
       else Global.state := Some (LuaTypeChecker.init !Global.name) ) ;
      parse lexbuf
  with 
    | ParsingError err          -> error (Debug.string_of_perr err)
    | TypeCheckingError err     -> ( Global.debug_ko () ; error (Debug.string_of_lerr err) )
    | Sys_error msg             -> error ("System error: "^msg)
    | IncorrectFileName         -> error ("Incorrect File Name.") (*FIXME*)
    | End_of_file               -> Hashtbl.reset Global.gs 

let _ = Arg.parse args main "Usage: dkparse file" 
  
