let caller = Sys.argv.(0)
let version = "%%VERSION%%"
let default_port = 8888
let default_target = Fpath.v "_site"

let program ~target =
  let open Yocaml in
  let* () = Task.move_javascript target in
  let* () = Task.move_css target in
  let* () = Task.move_images target in
  let* () = Task.process_articles target in
  let* () = Task.generate_feed target in
  let* () = Task.generate_tags target in
  Task.generate_index target
;;

let local_build _quiet target =
  Yocaml_unix.execute (program ~target:(Fpath.to_string target))
;;

module SSH = struct
  open Lwt.Infix

  type error = Unix.error * string * string

  type write_error =
    [ `Closed
    | `Error of Unix.error * string * string
    ]

  let pp_error ppf (err, f, v) =
    Fmt.pf ppf "%s(%s): %s" f v (Unix.error_message err)
  ;;

  let pp_write_error ppf = function
    | `Closed -> Fmt.pf ppf "Connection closed by peer"
    | `Error (err, f, v) ->
      Fmt.pf ppf "%s(%s): %s" f v (Unix.error_message err)
  ;;

  type flow =
    { ic : in_channel
    ; oc : out_channel
    }

  type endpoint =
    { user : string
    ; path : string
    ; host : Unix.inet_addr
    ; port : int
    ; capabilities : [ `Rd | `Wr ]
    }

  let pp_inet_addr ppf inet_addr =
    Fmt.string ppf (Unix.string_of_inet_addr inet_addr)
  ;;

  let connect { user; path; host; port; capabilities } =
    let edn = Fmt.str "%s@%a" user pp_inet_addr host in
    let cmd =
      match capabilities with
      | `Wr -> Fmt.str {sh|git-receive-pack '%s'|sh} path
      | `Rd -> Fmt.str {sh|git-upload-pack '%s'|sh} path
    in
    let cmd = Fmt.str "ssh -p %d %s %a" port edn Fmt.(quote string) cmd in
    try
      let ic, oc = Unix.open_process cmd in
      Lwt.return_ok { ic; oc }
    with
    | Unix.Unix_error (err, f, v) -> Lwt.return_error (`Error (err, f, v))
  ;;

  let read t =
    let tmp = Bytes.create 0x1000 in
    try
      let len = input t.ic tmp 0 0x1000 in
      if len = 0
      then Lwt.return_ok `Eof
      else Lwt.return_ok (`Data (Cstruct.of_bytes tmp ~off:0 ~len))
    with
    | Unix.Unix_error (err, f, v) -> Lwt.return_error (err, f, v)
  ;;

  let write t cs =
    let str = Cstruct.to_string cs in
    try
      output_string t.oc str;
      flush t.oc;
      Lwt.return_ok ()
    with
    | Unix.Unix_error (err, f, v) -> Lwt.return_error (`Error (err, f, v))
  ;;

  let writev t css =
    let rec go t = function
      | [] -> Lwt.return_ok ()
      | x :: r ->
        write t x
        >>= (function
        | Ok () -> go t r
        | Error _ as err -> Lwt.return err)
    in
    go t css
  ;;

  let close t =
    close_in t.ic;
    close_out t.oc;
    Lwt.return_unit
  ;;
end

let ssh_edn, ssh_protocol = Mimic.register ~name:"ssh" (module SSH)

let unix_ctx_with_ssh () =
  let open Lwt.Infix in
  Git_unix.ctx (Happy_eyeballs_lwt.create ())
  >|= fun ctx ->
  let open Mimic in
  let k0 scheme user path host port capabilities =
    match scheme, Unix.gethostbyname host with
    | `SSH, { Unix.h_addr_list; _ } when Array.length h_addr_list > 0 ->
      Lwt.return_some
        { SSH.user; path; host = h_addr_list.(0); port; capabilities }
    | _ -> Lwt.return_none
  in
  ctx
  |> Mimic.fold
       Smart_git.git_transmission
       Fun.[ req Smart_git.git_scheme ]
       ~k:(function
         | `SSH -> Lwt.return_some `Exec
         | _ -> Lwt.return_none)
  |> Mimic.fold
       ssh_edn
       Fun.
         [ req Smart_git.git_scheme
         ; req Smart_git.git_ssh_user
         ; req Smart_git.git_path
         ; req Smart_git.git_hostname
         ; dft Smart_git.git_port 22
         ; req Smart_git.git_capabilities
         ]
       ~k:k0
;;

let build_and_push _quiet target branch author author_email remote hook =
  let module Store = Irmin_unix.Git.FS.KV (Irmin.Contents.String) in
  let module Sync = Irmin.Sync.Make (Store) in
  let failwith_pull_error = function
    | Ok v -> Lwt.return v
    | Error (`Msg err) -> failwith err
    | Error (`Conflict err) -> Fmt.failwith "conflict: %s" err
  in
  let failwith_push_error = function
    | Ok v -> Lwt.return v
    | Error err -> Fmt.failwith "%a" Sync.pp_push_error err
  in
  let target = Fpath.to_string target in
  let config = Irmin_git.config target in
  let fiber () =
    let open Lwt.Infix in
    unix_ctx_with_ssh ()
    >>= fun ctx ->
    Store.remote ~ctx remote
    >>= fun upstream ->
    Store.Repo.v config
    >>= fun repository ->
    Store.of_branch repository branch
    >>= fun active_branch ->
    Sync.pull active_branch upstream `Set
    >|= failwith_pull_error
    >>= fun _ ->
    Yocaml_irmin.execute
      (module Yocaml_unix)
      (module Pclock)
      (module Store)
      ~author
      ~author_email:(Emile.to_string author_email)
      ~branch
      repository
      (program ~target:"")
    >>= fun () ->
    Sync.push active_branch upstream
    >|= failwith_push_error
    >>= fun _ ->
    match hook with
    | None -> Lwt.return_unit
    | Some hook ->
      Http_lwt_client.one_request
        ~config:(`HTTP_1_1 Httpaf.Config.default)
        ~meth:`GET
        (Uri.to_string hook)
      >>= (function
      | Ok (_response, _body) -> Lwt.return_unit
      | Error (`Msg err) -> failwith err)
  in
  Lwt_main.run (fiber ())
;;

let watch quiet target potential_port =
  let port = Option.value ~default:default_port potential_port in
  let () = local_build quiet target in
  let target = Fpath.to_string target in
  let server = Yocaml_unix.serve ~filepath:target ~port (program ~target) in
  Lwt_main.run server
;;

let common_options = "COMMON OPTIONS"

let verbosity =
  let open Cmdliner in
  let env = Cmd.Env.info "BLOGGER_LOGS" in
  Logs_cli.level ~docs:common_options ~env ()
;;

let renderer =
  let open Cmdliner in
  let env = Cmd.Env.info "BLOGGER_FMT" in
  Fmt_cli.style_renderer ~docs:common_options ~env ()
;;

let utf_8 =
  let open Cmdliner in
  let doc = "Allow binaries to emit UTF-8 characters." in
  let env = Cmd.Env.info "BLOGGER_UTF_8" in
  Arg.(value & opt bool true & info [ "with-utf-8" ] ~doc ~env)
;;

let reporter ppf =
  let report src level ~over k msgf =
    let k _ =
      over ();
      k ()
    in
    let with_metadata header _tags k ppf fmt =
      Fmt.kpf
        k
        ppf
        ("%a[%a]: " ^^ fmt ^^ "\n%!")
        Logs_fmt.pp_header
        (level, header)
        Fmt.(styled `Magenta string)
        (Logs.Src.name src)
    in
    msgf @@ fun ?header ?tags fmt -> with_metadata header tags k ppf fmt
  in
  { Logs.report }
;;

let setup_logs utf_8 style_renderer level =
  Fmt_tty.setup_std_outputs ~utf_8 ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (reporter Fmt.stderr);
  Option.is_none level
;;

let setup_logs =
  Cmdliner.Term.(const setup_logs $ utf_8 $ renderer $ verbosity)
;;

let man =
  let open Cmdliner in
  [ `S Manpage.s_authors; `P "blog.osau.re" ]
;;

let build_cmd =
  let open Cmdliner in
  let doc = Format.asprintf "Build the blog into the specified directory" in
  let exits = Cmd.Exit.defaults in
  let info = Cmd.info "build" ~version ~doc ~exits ~man in
  let path_arg =
    let doc =
      Format.asprintf
        "Specify where we build the website (default: %a)"
        Fpath.pp
        default_target
    in
    let arg = Arg.info ~doc [ "destination" ] in
    Arg.(value & opt (conv (Fpath.of_string, Fpath.pp)) default_target & arg)
  in
  Cmd.v info Term.(const local_build $ setup_logs $ path_arg)
;;

let watch_cmd =
  let open Cmdliner in
  let doc =
    Format.asprintf
      "Serve from the specified directory as an HTTP server and rebuild \
       website on demand"
  in
  let exits = Cmd.Exit.defaults in
  let path_arg =
    let doc =
      Format.asprintf
        "Specify where we build the website (default: %a)"
        Fpath.pp
        default_target
    in
    let arg = Arg.info ~doc [ "destination" ] in
    Arg.(value & opt (conv (Fpath.of_string, Fpath.pp)) default_target & arg)
  in
  let port_arg =
    let doc = Format.asprintf "The port (default: %d)" default_port in
    let arg = Arg.info ~doc [ "port"; "P"; "p" ] in
    Arg.(value & opt (some int) None & arg)
  in
  let info = Cmd.info "watch" ~version ~doc ~exits ~man in
  Cmd.v info Term.(const watch $ setup_logs $ path_arg $ port_arg)
;;

let push_cmd =
  let open Cmdliner in
  let doc =
    Format.asprintf
      "Push the blog (from the specified directory) into a Git repository"
  in
  let exits = Cmd.Exit.defaults in
  let path_arg =
    let doc =
      Format.asprintf
        "Specify where we build the website (default: %a)"
        Fpath.pp
        default_target
    in
    let arg = Arg.info ~doc [ "destination" ] in
    Arg.(value & opt (conv (Fpath.of_string, Fpath.pp)) default_target & arg)
  in
  let author_arg =
    let doc = "The author of the commit" in
    let arg = Arg.info ~doc [ "author" ] in
    Arg.(required & opt (some string) None & arg)
  in
  let author_email_arg =
    let email =
      Arg.conv
        ( Rresult.(
            fun str ->
              Emile.of_string str
              |> R.reword_error (R.msgf "%a" Emile.pp_error))
        , Emile.pp_mailbox )
    in
    let doc = "The email address of the author" in
    let arg = Arg.info ~doc [ "email" ] in
    Arg.(required & opt (some email) None & arg)
  in
  let branch_arg =
    let doc = "The active Git branch name" in
    let arg = Arg.info ~doc [ "b"; "branch" ] in
    Arg.(value & opt string "master" & arg)
  in
  let remote_arg =
    let remote =
      let parser str =
        match Smart_git.Endpoint.of_string str with
        | Ok _ -> Ok str
        | Error _ as err -> err
      in
      Arg.conv (parser, Fmt.string)
    in
    let doc = "The remote Git repository" in
    let arg = Arg.info ~doc [ "r"; "remote" ] in
    Arg.(required & opt (some remote) None & arg)
  in
  let hook_arg =
    let doc = "The URL of the hook to update the unikernel" in
    let arg = Arg.info ~doc [ "h"; "hook" ] in
    let of_string str =
      match Uri.of_string str with
      | v -> Ok v
      | exception _ -> Rresult.R.error_msgf "Invalid URI: %s" str
    in
    Arg.(value & opt (some (conv (of_string, Uri.pp))) None & arg)
  in
  let info = Cmd.info "push" ~version ~doc ~exits ~man in
  Cmd.v
    info
    Term.(
      const build_and_push
      $ setup_logs
      $ path_arg
      $ branch_arg
      $ author_arg
      $ author_email_arg
      $ remote_arg
      $ hook_arg)
;;

let cmd =
  let open Cmdliner in
  let sdocs = Manpage.s_common_options in
  let doc = "Build, push or serve my personal website" in
  let default_info = Cmd.info caller ~version ~doc ~sdocs ~man in
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  Cmd.group ~default default_info [ build_cmd; watch_cmd; push_cmd ]
;;

let () = exit @@ Cmdliner.Cmd.eval cmd
