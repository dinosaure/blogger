open Yocaml
module Metaformat = Yocaml_yaml
module Markup = Yocaml_markdown
module Template = Yocaml_jingoo

let target = "_site/"
let css_target = "css" |> into target
let javascript_target = "js" |> into target
let fonts_target = "fonts" |> into target
let images_target = "images" |> into target
let template file = add_extension file "html" |> into "templates"
let article_template = template "article"
let layout_template = template "layout"
let list_template = template "list_articles"
let article_target file = Model.article_path file |> into target
let binary_update = Build.watch Sys.argv.(0)
let index_html = "index.html" |> into target
let index_md = "index.md" |> into "pages"
let rss_feed = "feed.xml" |> into target
let tag_file tag = Model.tag_path tag |> into target
let tag_template = template "tag"

let move_css =
  process_files [ "css" ] File.is_css (Build.copy_file ~into:css_target)
;;

let move_fonts =
  process_files
    [ "fonts" ]
    (Fun.const true)
    (Build.copy_file ~into:fonts_target)
;;

let move_javascript =
  process_files
    [ "js" ]
    File.is_javascript
    (Build.copy_file ~into:javascript_target)
;;

let move_images =
  process_files
    [ "images" ]
    File.is_image
    (Build.copy_file ~into:images_target)
;;

let process_articles =
  process_files [ "articles" ] File.is_markdown (fun article_file ->
      let open Build in
      create_file
        (article_target article_file)
        (binary_update
        >>> Metaformat.read_file_with_metadata
              (module Model.Article)
              article_file
        >>> Markup.content_to_html ()
        >>> Template.apply_as_template (module Model.Article) article_template
        >>> Template.apply_as_template (module Model.Article) layout_template
        >>^ Stdlib.snd))
;;

let merge_with_page ((meta, content), articles) =
  let title = Metadata.Page.title meta in
  let description = Metadata.Page.description meta in
  Model.Articles.make ?title ?description articles, content
;;

let generate_feed =
  let open Build in
  let* articles_arrow =
    Collection.Articles.get_all (module Metaformat) "articles"
  in
  create_file
    rss_feed
    (binary_update >>> articles_arrow >>^ Feed.make >>^ Rss.Channel.to_rss)
;;

let generate_tags =
  let* deps, tags = Collection.Tags.compute (module Metaformat) "articles" in
  let tags_string = List.map (fun (i, s) -> i, List.length s) tags in
  let mk_meta tag articles () = Model.Tag.make tag articles tags_string, "" in
  List.fold_left
    (fun program (tag, articles) ->
      let open Build in
      program
      >> create_file
           (tag_file tag)
           (init deps
           >>> binary_update
           >>^ mk_meta tag articles
           >>> Template.apply_as_template (module Model.Tag) tag_template
           >>> Template.apply_as_template (module Model.Tag) layout_template
           >>^ Stdlib.snd))
    (return ())
    tags
;;

let generate_index =
  let open Build in
  let* articles_arrow =
    Collection.Articles.get_all (module Metaformat) "articles"
  in
  create_file
    index_html
    (binary_update
    >>> Metaformat.read_file_with_metadata (module Metadata.Page) index_md
    >>> Markup.content_to_html ()
    >>> articles_arrow
    >>^ merge_with_page
    >>> Template.apply_as_template (module Model.Articles) list_template
    >>> Template.apply_as_template (module Model.Articles) layout_template
    >>^ Stdlib.snd)
;;
