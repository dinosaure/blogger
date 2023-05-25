open Yocaml

let to_html ~strict =
  Build.arrow $ fun str ->
  Cmarkit_html.of_doc ~safe:false (Cmarkit.Doc.of_string ~strict str)

let content_to_html ?(strict= true) () = Build.snd (to_html ~strict)
