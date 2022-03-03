let caller = Sys.argv.(0)
let version = "dev"
let default_port = 8888

let program =
  let open Yocaml in
  let* () = Task.move_fonts in
  let* () = Task.move_javascript in
  let* () = Task.move_css in
  let* () = Task.move_images in
  let* () = Task.process_articles in
  let* () = Task.generate_feed in
  let* () = Task.generate_tags in
  Task.generate_index
;;

let build () = Yocaml_unix.execute program

let watch potential_port =
  let port = Option.value ~default:default_port potential_port in
  let () = build () in
  let server = Yocaml_unix.serve ~filepath:Task.target ~port program in
  Lwt_main.run server
;;

let man =
  let open Cmdliner in
  [ `S Manpage.s_authors; `P "The <XHTMLBoy/>" ]
;;

let build_cmd =
  let open Cmdliner in
  let doc = Format.asprintf "Build the blog into [%s]" Task.target in
  let exits = Cmd.Exit.defaults in
  let info = Cmd.info "build" ~version ~doc ~exits ~man in
  Cmd.v info Term.(const build $ const ())
;;

let watch_cmd =
  let open Cmdliner in
  let doc =
    Format.asprintf
      "Serve [%s] as an HTTP server and rebuild website on demand"
      Task.target
  in
  let exits = Cmd.Exit.defaults in
  let port_arg =
    let doc = Format.asprintf "The port (default: %d)" default_port in
    let arg = Arg.info ~doc [ "port"; "P"; "p" ] in
    Arg.(value & opt (some int) None & arg)
  in
  let info = Cmd.info "watch" ~version ~doc ~exits ~man in
  Cmd.v info Term.(const watch $ port_arg)
;;

let index =
  let open Cmdliner in
  let sdocs = Manpage.s_common_options in
  let doc = "Build or serve my personal website" in
  let info = Cmd.info "darcs" ~version:"%%VERSION%%" ~doc ~sdocs ~man in
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  Cmd.group info ~default [ build_cmd; watch_cmd ]
;;

let () =
  let () = Logs.set_level ~all:true (Some Logs.Info) in
  let () = Logs.set_reporter (Logs_fmt.reporter ()) in
  let open Cmdliner in
  exit (Cmd.eval index)
;;
