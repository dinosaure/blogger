let reporter ppf =
  let report src level ~over k msgf =
    let k _ =
      over ();
      k ()
    in
    let with_metadata header _tags k ppf fmt =
      Format.kfprintf k ppf
        ("%a[%a]: " ^^ fmt ^^ "\n%!")
        Logs_fmt.pp_header (level, header)
        Fmt.(styled `Magenta string)
        (Logs.Src.name src)
    in
    msgf @@ fun ?header ?tags fmt -> with_metadata header tags k ppf fmt
  in
  { Logs.report }

let () = Fmt_tty.setup_std_outputs ~style_renderer:`Ansi_tty ~utf_8:true ()
let () = Logs.set_reporter (reporter Fmt.stdout)
(* let () = Logs.set_level ~all:true (Some Logs.Debug) *)
let author = ref "Romain Calascibetta"
let email = ref "romain.calascibetta@gmail.com"
let message = ref "Pushed by YOCaml 2"
let remote = ref "git@github.com:dinosaure/blogger.git#gh-pages"
let host = ref "https://blog.osau.re"

module Source = Yocaml_git.From_identity (Yocaml_unix.Runtime)

let usage =
  Fmt.str
    "%s [--message <message>] [--author <author>] [--email <email>] -r \
     <repository>"
    Sys.argv.(0)

let specification =
  [
    ("--message", Arg.Set_string message, "The commit message")
  ; ("--email", Arg.Set_string email, "The email used to craft the commit")
  ; ("-r", Arg.Set_string remote, "The Git repository")
  ; ("--author", Arg.Set_string author, "The Git commit author")
  ; ("--host", Arg.Set_string host, "The host where the blog is available")
  ]

let () =
  Arg.parse specification ignore usage;
  let author = !author
  and email = !email
  and message = !message
  and remote = !remote in
  let module Blog = Blog.Make_with_target (struct
    let source = Yocaml.Path.rel []
    let target = Yocaml.Path.rel []
  end) in
  Yocaml_git.run
    (module Source)
    (module Pclock)
    ~context:`SSH ~author ~email ~message ~remote
    (fun () -> Blog.process_all ~host:!host)
  |> Lwt_main.run
  |> Result.iter_error (fun (`Msg err) -> invalid_arg err)
