let port = ref 8000
let usage = Fmt.str "%s [--port <port>]" Sys.argv.(0)

let specification =
  [ ("--port", Arg.Set_int port, "The port where we serve the website") ]

module Dest = Blog.Make (struct
  let source = Yocaml.Path.rel []
end)

let () =
  Arg.parse specification ignore usage;
  let host = Fmt.str "http://localhost:%d" !port in
  Yocaml_unix.serve ~level:`Info ~target:Dest.target ~port:!port
  @@ fun () -> Dest.process_all ~host
