open Yocaml


let target = "_site/"
let articles_repository = "articles"
let track_binary_update = Build.watch Sys.argv.(0)
let global_layout = into "templates" "layout.html"
let article_layout = into "templates" "article.html"
let list_layout = into "templates" "list_articles.html"
let is_css = with_extension "css"

let is_images =
  let open Preface.Predicate in
  with_extension "png" || with_extension "svg"
;;

let is_markdown =
  let open Preface.Predicate in
  with_extension "md" || with_extension "markdown"
;;

let get_article_url source =
  let filename = basename $ replace_extension source "html" in
  into "articles" filename
;;

let css =
  let open Build in
  process_files [ "css/" ] is_css
  $ fun css_file -> copy_file css_file ~into:(into target "css")
;;

let images =
  let open Build in
  process_files [ "images/" ] is_images
  $ fun image_file -> copy_file image_file ~into:(into target "images")
;;

let prepare_article source =
  let open Build in
  track_binary_update
  >>> Yocaml_yaml.read_file_with_metadata (module Metadata.Article) source
  >>> Yocaml_markdown.content_to_html ()
  >>> apply_as_template (module Metadata.Article) article_layout
  >>> apply_as_template (module Metadata.Article) global_layout
;;

let articles =
  process_files [ articles_repository ] is_markdown
  $ fun file ->
  let open Build in
  create_file
    (into target $ get_article_url file)
    (prepare_article file >>^ Preface.Pair.snd)
;;

let index =
  let open Build in
  let* list_articles =
    collection
      (read_child_files "articles/" (with_extension "md"))
      (fun source ->
        track_binary_update
        >>> Yocaml_yaml.read_file_with_metadata
              (module Metadata.Article)
              source
        >>^ fun (x, _) -> x, get_article_url source)
      (fun x meta content ->
        x
        |> Metadata.Articles.make
             ?title:(Metadata.Page.title meta)
             ?description:(Metadata.Page.description meta)
        |> Metadata.Articles.sort_articles_by_date
        |> fun x -> x, content)
  in

  create_file
    (into target "index.html")
    (track_binary_update
    >>> Yocaml_yaml.read_file_with_metadata
          (module Metadata.Page)
          (into "pages" "index.md")
    >>> Yocaml_markdown.content_to_html ()
    >>> list_articles
    >>> apply_as_template (module Metadata.Articles) list_layout
    >>> apply_as_template (module Metadata.Articles) global_layout
    >>^ Preface.Pair.snd)
;;

let () =
  let program =
    let* () = css in
    let* () = images in
    let* () = articles in
    index
  in
  Yocaml_unix.execute program
;;
