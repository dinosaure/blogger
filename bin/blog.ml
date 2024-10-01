open Yocaml

let is_empty_list = function [] -> true | _ -> false

module Date = struct
  type month =
    | Jan
    | Feb
    | Mar
    | Apr
    | May
    | Jun
    | Jul
    | Aug
    | Sep
    | Oct
    | Nov
    | Dec

  type day_of_week = Mon | Tue | Wed | Thu | Fri | Sat | Sun
  type year = int
  type day = int
  type hour = int
  type min = int
  type sec = int

  type t = {
      year : year
    ; month : month
    ; day : day
    ; hour : hour
    ; min : min
    ; sec : sec
  }

  let invalid_int x message =
    Data.Validation.fail_with ~given:(string_of_int x) message

  let month_from_int x =
    if x > 0 && x <= 12 then
      Result.ok
        [| Jan; Feb; Mar; Apr; May; Jun; Jul; Aug; Sep; Oct; Nov; Dec |].(x - 1)
    else invalid_int x "Invalid month value"

  let year_from_int x =
    if x >= 0 then Result.ok x else invalid_int x "Invalid year value"

  let is_leap year =
    if year mod 100 = 0 then year mod 400 = 0 else year mod 4 = 0

  let days_in_month year month =
    match month with
    | Jan | Mar | May | Jul | Aug | Oct | Dec -> 31
    | Feb -> if is_leap year then 29 else 28
    | _ -> 30

  let day_from_int year month x =
    let dim = days_in_month year month in
    if x >= 1 && x <= dim then Result.ok x
    else invalid_int x "Invalid day value"

  let hour_from_int x =
    if x >= 0 && x < 24 then Result.ok x else invalid_int x "Invalid hour value"

  let min_from_int x =
    if x >= 0 && x < 60 then Result.ok x else invalid_int x "Invalid min value"

  let sec_from_int x =
    if x >= 0 && x < 60 then Result.ok x else invalid_int x "Invalid sec value"

  let ( let* ) = Result.bind

  let make ?(time = (0, 0, 0)) ~year ~month ~day () =
    let hour, min, sec = time in
    let* year = year_from_int year in
    let* month = month_from_int month in
    let* day = day_from_int year month day in
    let* hour = hour_from_int hour in
    let* min = min_from_int min in
    let* sec = sec_from_int sec in
    Result.ok { year; month; day; hour; min; sec }

  let validate_from_datetime_str str =
    let str = String.trim str in
    match
      Scanf.sscanf_opt str "%04d%c%02d%c%02d%c%02d%c%02d%c%02d"
        (fun year _ month _ day _ hour _ min _ sec ->
          ((hour, min, sec), year, month, day))
    with
    | None -> Data.Validation.fail_with ~given:str "Invalid date format"
    | Some (time, year, month, day) -> make ~time ~year ~month ~day ()

  let validate_from_date_str str =
    let str = String.trim str in
    match
      Scanf.sscanf_opt str "%04d%c%02d%c%02d" (fun year _ month _ day ->
          (year, month, day))
    with
    | None -> Data.Validation.fail_with ~given:str "Invalid date format"
    | Some (year, month, day) -> make ~year ~month ~day ()

  let validate =
    let open Data.Validation in
    string & (validate_from_datetime_str / validate_from_date_str)

  let month_to_int = function
    | Jan -> 1
    | Feb -> 2
    | Mar -> 3
    | Apr -> 4
    | May -> 5
    | Jun -> 6
    | Jul -> 7
    | Aug -> 8
    | Sep -> 9
    | Oct -> 10
    | Nov -> 11
    | Dec -> 12

  let dow_to_int = function
    | Mon -> 0
    | Tue -> 1
    | Wed -> 2
    | Thu -> 3
    | Fri -> 4
    | Sat -> 5
    | Sun -> 6

  let compare_date a b =
    let cmp = Int.compare a.year b.year in
    if Int.equal cmp 0 then
      let cmp = Int.compare (month_to_int a.month) (month_to_int b.month) in
      if Int.equal cmp 0 then Int.compare a.day b.day else cmp
    else cmp

  let compare_time a b =
    let cmp = Int.compare a.hour b.hour in
    if Int.equal cmp 0 then
      let cmp = Int.compare a.min b.min in
      if Int.equal cmp 0 then Int.compare a.sec b.sec else cmp
    else cmp

  let compare a b =
    let cmp = compare_date a b in
    if Int.equal cmp 0 then compare_time a b else cmp

  let pp_date ppf { year; month; day; _ } =
    Format.fprintf ppf "%04d-%02d-%02d" year (month_to_int month) day

  let month_value = function
    | Jan -> 0
    | Feb -> 3
    | Mar -> 3
    | Apr -> 6
    | May -> 1
    | Jun -> 4
    | Jul -> 6
    | Aug -> 2
    | Sep -> 5
    | Oct -> 0
    | Nov -> 3
    | Dec -> 5

  let day_of_week { year; month; day; _ } =
    let yy = year mod 100 in
    let cc = (year - yy) / 100 in
    let c_code = [| 6; 4; 2; 0 |].(cc mod 4) in
    let y_code = (yy + (yy / 4)) mod 7 in
    let m_code =
      let v = month_value month in
      if is_leap year && (month = Jan || month = Feb) then v - 1 else v
    in
    let index = (c_code + y_code + m_code + day) mod 7 in
    [| Sun; Mon; Tue; Wed; Thu; Fri; Sat |].(index)

  let normalize ({ year; month; day; hour; min; sec } as dt) =
    let day_of_week = day_of_week dt in
    let open Data in
    record
      [
        ("year", int year); ("month", int (month_to_int month)); ("day", int day)
      ; ("hour", int hour); ("min", int min); ("sec", int sec)
      ; ("day_of_week", int (dow_to_int day_of_week))
      ; ("human", string (Format.asprintf "%a" pp_date dt))
      ]

  let to_archetype_date_time { year; month; day; hour; min; sec } =
    let time = (hour, min, sec) in
    let month = month_to_int month in
    Result.get_ok (Archetype.Datetime.make ~time ~year ~month ~day ())
end

module Page = struct
  let entity_name = "Page"

  class type t = object ('self)
    method title : string option
    method charset : string option
    method description : string option
    method tags : string list
    method with_host : string -> 'self
    method get_host : string option
  end

  class page ?title ?description ?charset ?(tags = []) () =
    object (_ : #t)
      method title = title
      method charset = charset
      method description = description
      method tags = tags
      val host = None
      method with_host v = {< host = Some v >}
      method get_host = host
    end

  let neutral = Result.ok @@ new page ()

  let validate fields =
    let open Data.Validation in
    let+ title = optional fields "title" string
    and+ description = optional fields "description" string
    and+ charset = optional fields "charset" string
    and+ tags = optional_or fields ~default:[] "tags" (list_of string) in
    new page ?title ?description ?charset ~tags ()

  let validate =
    let open Data.Validation in
    record validate
end

module Author = struct
  class type t = object
    method name : string
    method link : string
    method email : string
    method avatar : string option
  end

  let gravatar email =
    let tk = String.(lowercase_ascii (trim email)) in
    let hs = Digest.(to_hex (string tk)) in
    "https://www.gravatar.com/avatar/" ^ hs

  class author ~name ~link ~email ?(avatar = gravatar email) () =
    object (_ : #t)
      method name = name
      method link = link
      method email = email
      method avatar = Some avatar
    end

  let validate fields =
    let open Data.Validation in
    let+ name = required fields "name" string
    and+ link = required fields "link" string
    and+ email = required fields "email" string
    and+ avatar = optional fields "avatar" string in
    match avatar with
    | None -> new author ~name ~link ~email ()
    | Some avatar -> new author ~name ~link ~email ~avatar ()

  let validate =
    let open Data.Validation in
    record validate

  let normalize obj =
    let open Data in
    record
      [
        ("name", string obj#name); ("link", string obj#link)
      ; ("email", string obj#email); ("avatar", option string obj#avatar)
      ]
end

let romain_calascibetta =
  new Author.author
    ~name:"Romain Calascibetta" ~link:"https://blog.osau.re/"
    ~email:"romain.calascibetta@gmail.com" ()

module Article = struct
  let entity_name = "Article"

  class type t = object ('self)
    method title : string
    method description : string
    method charset : string option
    method tags : string list
    method date : Date.t
    method author : Author.t
    method co_authors : Author.t list
    method with_host : string -> 'self
    method get_host : string option
  end

  class article ~title ~description ?charset ?(tags = []) ~date ~author
    ?(co_authors = []) () =
    object (_ : #t)
      method title = title
      method description = description
      method charset = charset
      method tags = tags
      method date = date
      method author = author
      method co_authors = co_authors
      val host = None
      method with_host v = {< host = Some v >}
      method get_host = host
    end

  let title p = p#title
  let description p = p#description
  let tags p = p#tags
  let date p = p#date

  let neutral =
    Data.Validation.fail_with ~given:"null" "Cannot be null"
    |> Result.map_error (fun error ->
           Required.Validation_error { entity = entity_name; error })

  let validate fields =
    let open Data.Validation in
    let+ title = required fields "title" string
    and+ description = required fields "description" string
    and+ charset = optional fields "charset" string
    and+ tags = optional_or fields ~default:[] "tags" (list_of string)
    and+ date = required fields "date" Date.validate
    and+ author =
      optional_or fields ~default:romain_calascibetta "author" Author.validate
    and+ co_authors =
      optional_or fields ~default:[] "co-authors" (list_of Author.validate)
    in
    new article ~title ~description ?charset ~tags ~date ~author ~co_authors ()

  let validate =
    let open Data.Validation in
    record validate

  let normalize obj =
    Data.
      [
        ("title", string obj#title); ("description", string obj#description)
      ; ("date", Date.normalize obj#date); ("charset", option string obj#charset)
      ; ("tags", list_of string obj#tags)
      ; ("author", Author.normalize obj#author)
      ; ("co-authors", list_of Author.normalize obj#co_authors)
      ; ("host", option string obj#get_host)
      ]
end

module Articles = struct
  class type t = object ('self)
    method title : string option
    method description : string option
    method articles : (Path.t * Article.t) list
    method with_host : string -> 'self
    method get_host : string option
  end

  class articles ?title ?description articles =
    object (_ : #t)
      method title = title
      method description = description
      method articles = articles
      val host = None
      method with_host v = {< host = Some v >}
      method get_host = host
    end

  let sort_by_date ?(increasing = false) articles =
    List.sort
      (fun (_, articleA) (_, articleB) ->
        let r = Date.compare articleA#date articleB#date in
        if increasing then r else ~-r)
      articles

  let fetch (module P : Required.DATA_PROVIDER) ?increasing
      ?(filter = fun x -> x) ?(on = `Source) ~where ~compute_link path =
    Task.from_effect begin fun () ->
        let open Eff in
        let* files = read_directory ~on ~only:`Files ~where path in
        let+ articles =
          List.traverse
            (fun file ->
              let url = compute_link file in
              let+ metadata, _content =
                Eff.read_file_with_metadata (module P) (module Article) ~on file
              in
              (url, metadata))
            files
        in
        articles |> sort_by_date ?increasing |> filter end

  let compute_index (module P : Required.DATA_PROVIDER) ?increasing
      ?(filter = fun x -> x) ?(on = `Source) ~where ~compute_link path =
    let open Task in
    (fun x -> (x, ()))
    |>> second
          (fetch (module P) ?increasing ~filter ~on ~where ~compute_link path)
    >>> lift (fun (v, articles) ->
            new articles ?title:v#title ?description:v#description articles)

  let normalize (ident, article) =
    let open Data in
    record (("url", string @@ Path.to_string ident) :: Article.normalize article)

  let normalize obj =
    let open Data in
    [
      ("articles", list_of normalize obj#articles)
    ; ("has_articles", bool @@ is_empty_list obj#articles)
    ; ("title", option string obj#title)
    ; ("description", option string obj#description)
    ; ("host", option string obj#get_host)
    ]
end

module Make_with_target (S : sig
  val source : Path.t
  val target : Path.t
end) =
struct
  let source_root = S.source

  module Source = struct
    let css = Path.(source_root / "css")
    let js = Path.(source_root / "js")
    let images = Path.(source_root / "images")
    let articles = Path.(source_root / "articles")
    let index = Path.(source_root / "pages" / "index.md")
    let templates = Path.(source_root / "templates")
    let template file = Path.(templates / file)
    let binary = Path.rel [ Sys.argv.(0) ]
    let cache = Path.(source_root / "_cache")
  end

  module Target = struct
    let target_root = S.target
    let pages = target_root
    let articles = Path.(target_root / "articles")
    let rss1 = Path.(target_root / "rss1.xml")
    let rss2 = Path.(target_root / "feed.xml")
    let atom = Path.(target_root / "atom.xml")

    let as_html into file =
      file |> Path.move ~into |> Path.change_extension "html"
  end

  let target = Target.target_root

  let process_css_files =
    Action.copy_directory ~into:Target.target_root Source.css

  let process_js_files =
    Action.copy_directory ~into:Target.target_root Source.js

  let process_images_files =
    Action.copy_directory ~into:Target.target_root Source.images

  let process_article ~host file =
    let file_target = Target.(as_html articles file) in
    let open Task in
    Action.write_static_file file_target
      begin
        Pipeline.track_file Source.binary
        >>> Yocaml_yaml.Pipeline.read_file_with_metadata (module Article) file
        >>* (fun (obj, str) -> Eff.return (obj#with_host host, str))
        >>> Yocaml_cmarkit.content_to_html ()
        >>> Yocaml_jingoo.Pipeline.as_template
              (module Article)
              (Source.template "article.html")
        >>> Yocaml_jingoo.Pipeline.as_template
              (module Article)
              (Source.template "layout.html")
        >>> drop_first ()
      end

  let process_articles ~host =
    Action.batch ~only:`Files ~where:(Path.has_extension "md") Source.articles
      (process_article ~host)

  let process_index ~host =
    let file = Source.index in
    let file_target = Target.(as_html pages file) in

    let open Task in
    let compute_index =
      Articles.compute_index
        (module Yocaml_yaml)
        ~where:(Path.has_extension "md")
        ~compute_link:(Target.as_html @@ Path.abs [ "articles" ])
        Source.articles
    in

    Action.write_static_file file_target
      begin
        Pipeline.track_files [ Source.binary; Source.articles ]
        >>> Yocaml_yaml.Pipeline.read_file_with_metadata (module Page) file
        >>> Yocaml_cmarkit.content_to_html ()
        >>> first compute_index
        >>* (fun (obj, str) -> Eff.return (obj#with_host host, str))
        >>> Yocaml_jingoo.Pipeline.as_template ~strict:true
              (module Articles)
              (Source.template "index.html")
        >>> Yocaml_jingoo.Pipeline.as_template ~strict:true
              (module Articles)
              (Source.template "layout.html")
        >>> drop_first ()
      end

  let feed_title = "The dinosaure's blog"
  let site_url = "https://blog.osau.re"
  let feed_description = "My personnal blog about MirageOS & OCaml"

  let fetch_articles =
    let open Task in
    Pipeline.track_files [ Source.binary; Source.articles ]
    >>> Articles.fetch
          (module Yocaml_yaml)
          ~where:(Path.has_extension "md")
          ~compute_link:(Target.as_html @@ Path.abs [ "articles" ])
          Source.articles

  let rss1 =
    let from_articles ~title ~site_url ~description ~feed_url () =
      let open Yocaml_syndication in
      Rss1.from ~title ~url:feed_url ~link:site_url ~description
      @@ fun (path, article) ->
      let title = Article.title article in
      let link = site_url ^ Yocaml.Path.to_string path in
      let description = Article.description article in
      Rss1.item ~title ~link ~description
    in
    let open Task in
    Action.write_static_file Target.rss1
      begin
        fetch_articles
        >>> from_articles ~title:feed_title ~site_url
              ~description:feed_description
              ~feed_url:"https://blog.osau.re/rss1.xml" ()
      end

  let rss2 =
    let open Task in
    let from_articles ~title ~site_url ~description ~feed_url () =
      let open Yocaml_syndication in
      lift
        begin
          fun articles ->
            let last_build_date =
              List.fold_left
                begin
                  fun acc (_, elt) ->
                    let v = Date.to_archetype_date_time (Article.date elt) in
                    match acc with
                    | None -> Some v
                    | Some a ->
                        if Archetype.Datetime.compare a v > 0 then Some a
                        else Some v
                end
                None articles
              |> Option.map Datetime.make
            in
            let feed =
              Rss2.feed ?last_build_date ~title ~link:site_url ~url:feed_url
                ~description
                begin
                  fun (path, article) ->
                    let title = Article.title article in
                    let link = site_url ^ Path.to_string path in
                    let guid = Rss2.guid_from_link in
                    let description = Article.description article in
                    let pub_date =
                      Datetime.make
                        (Date.to_archetype_date_time (Article.date article))
                    in
                    Rss2.item ~title ~link ~guid ~description ~pub_date ()
                end
                articles
            in
            Xml.to_string feed
        end
    in
    Action.write_static_file Target.rss2
      begin
        fetch_articles
        >>> from_articles ~title:feed_title ~site_url
              ~description:feed_description
              ~feed_url:"https://blog.osau.re/feed.xml" ()
      end

  let atom =
    let open Task in
    let open Yocaml_syndication in
    let authors = Yocaml.Nel.singleton @@ Person.make "Romain Calascibetta" in
    let from_articles ?(updated = Atom.updated_from_entries ()) ?(links = [])
        ?id ~site_url ~authors ~title ~feed_url () =
      let id = Option.value ~default:feed_url id in
      let feed_url = Atom.self feed_url in
      let base_url = Atom.link site_url in
      let links = base_url :: feed_url :: links in
      Atom.from ~links ~updated ~title ~authors ~id
        begin
          fun (path, article) ->
            let title = Article.title article in
            let content_url = site_url ^ Yocaml.Path.to_string path in
            let updated =
              Datetime.make (Date.to_archetype_date_time (Article.date article))
            in
            let categories = List.map Category.make (Article.tags article) in
            let summary = Atom.text (Article.description article) in
            let links = [ Atom.alternate content_url ~title ] in
            Atom.entry ~links ~categories ~summary ~updated ~id:content_url
              ~title:(Atom.text title) ()
        end
    in
    Action.write_static_file Target.atom
      begin
        fetch_articles
        >>> from_articles ~site_url ~authors ~title:(Atom.text feed_title)
              ~feed_url:"https://blog.osau.re/atom.xml" ()
      end

  let process_all ~host =
    let open Eff in
    Action.restore_cache ~on:`Source Source.cache
    >>= process_css_files >>= process_js_files >>= process_images_files
    >>= process_articles ~host >>= process_index ~host >>= rss1 >>= rss2 >>= atom
    >>= Action.store_cache ~on:`Source Source.cache
end

module Make (S : sig
  val source : Path.t
end) =
Make_with_target (struct
  include S

  let target = Path.(source / "_site")
end)
