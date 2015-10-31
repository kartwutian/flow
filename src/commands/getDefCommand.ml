(**
 * Copyright (c) 2014, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "flow" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

(***********************************************************************)
(* flow get-def command *)
(***********************************************************************)

module Json = Hh_json

open CommandUtils

let spec = {
  CommandSpec.
  name = "get-def";
  doc = "Gets the definition location of a variable or property";
  usage = Printf.sprintf
    "Usage: %s get-def [OPTION]... [FILE] LINE COLUMN\n\n\
      e.g. %s get-def foo.js 12 3\n\
      or   %s get-def 12 3 < foo.js\n"
      CommandUtils.exe_name
      CommandUtils.exe_name
      CommandUtils.exe_name;
  args = CommandSpec.ArgSpec.(
    empty
    |> server_flags
    |> root_flag
    |> json_flags
    |> strip_root_flag
    |> flag "--path" (optional string)
        ~doc:"Specify (fake) path to file when reading data from stdin"
    |> anon "args" (required (list_of string)) ~doc:"[FILE] LINE COL"
  )
}

let parse_args path args =
  let (file, line, column) = match args with
  | [file; line; column] ->
      let file = expand_path file in
      ServerProt.FileName file, (int_of_string line), (int_of_string column)
  | [line; column] ->
      get_file_from_filename_or_stdin path None,
      (int_of_string line),
      (int_of_string column)
  | _ ->
      CommandSpec.usage spec;
      FlowExitStatus.(exit Commandline_usage_error)
  in
  let (line, column) = convert_input_pos (line, column) in
  file, line, column

(* get-def command handler.
   - json toggles JSON output
   - strip_root toggles whether output positions are relativized w.r.t. root
   - path is a user-specified path to use as incoming content source path
   - args is mandatory command args; see parse_args above
 *)
let main option_values root json strip_root path args () =
  let (file, line, column) = parse_args path args in
  let root = guess_root (
    match root with
    | Some root -> Some root
    | None -> ServerProt.path_of_input file
  ) in
  (* connect to server *)
  let ic, oc = connect option_values root in
  (* dispatch command *)
  ServerProt.cmd_to_channel oc
    (ServerProt.GET_DEF (file, line, column));
  (* command result will be a position structure with full file path *)
  let loc:Loc.t = Marshal.from_channel ic in
  (* if strip_root has been specified, relativize path to root *)
  let loc = relativize strip_root root loc in
  (* format output *)
  if json
  then (
    let json = Json.JAssoc (Errors_js.json_of_loc loc) in
    let json = Json.json_to_string json in
    print_endline json;
  ) else
    if option_values.from = "vim" || option_values.from = "emacs"
    then print_endline (Errors_js.string_of_loc_deprecated loc)
    else print_endline (range_string_of_loc loc)

let command = CommandSpec.command spec main
