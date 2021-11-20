open Yocaml

let () =
  let program =
    let* () = Task.move_fonts in
    let* () = Task.move_javascript in
    let* () = Task.move_css in
    let* () = Task.move_images in
    let* () = Task.process_articles in
    let* () = Task.generate_feed in
    let* () = Task.generate_tags in
    Task.generate_index
  in
  Yocaml_unix.execute program
;;
