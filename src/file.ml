open Yocaml

let is_css = with_extension "css"
let is_javascript = with_extension "js"

let is_image =
  let open Preface.Predicate in
  with_extension "png"
  || with_extension "svg"
  || with_extension "jpg"
  || with_extension "jpeg"
  || with_extension "gif"
;;

let is_markdown =
  let open Preface.Predicate in
  with_extension "md" || with_extension "markdown"
;;
