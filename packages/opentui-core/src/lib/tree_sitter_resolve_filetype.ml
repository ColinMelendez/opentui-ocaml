let normalize value = String.lowercase_ascii (String.trim value)

let normalize_filetype_token value =
  let value = normalize value in
  if String.length value > 0 && Char.equal (String.get value 0) '.' then
    String.sub value 1 (String.length value - 1)
  else value

let extension_map =
  [
    ("astro", "astro"); ("bash", "bash"); ("c", "c");
    ("cc", "cpp"); ("cjs", "javascript"); ("clj", "clojure");
    ("cpp", "cpp"); ("cxx", "cpp"); ("cs", "csharp");
    ("cts", "typescript"); ("ctsx", "typescriptreact"); ("dart", "dart");
    ("diff", "diff"); ("edn", "clojure"); ("go", "go");
    ("gemspec", "ruby"); ("groovy", "groovy"); ("h", "c");
    ("handlebars", "handlebars"); ("hbs", "handlebars");
    ("hh", "cpp"); ("hpp", "cpp"); ("hxx", "cpp"); ("h++", "cpp");
    ("hrl", "erlang"); ("hs", "haskell"); ("htm", "html");
    ("html", "html"); ("ini", "ini"); ("js", "javascript");
    ("jsx", "javascriptreact"); ("jl", "julia"); ("json", "json");
    ("ksh", "bash"); ("kt", "kotlin"); ("kts", "kotlin");
    ("latex", "latex"); ("less", "less"); ("lua", "lua");
    ("markdown", "markdown"); ("md", "markdown"); ("mdown", "markdown");
    ("mkd", "markdown"); ("mjs", "javascript"); ("ml", "ocaml");
    ("mli", "ocaml"); ("mts", "typescript"); ("mtsx", "typescriptreact");
    ("php", "php"); ("pl", "perl"); ("pm", "perl"); ("ps1", "powershell");
    ("psm1", "powershell"); ("py", "python"); ("pyi", "python");
    ("r", "r"); ("rb", "ruby"); ("rake", "ruby"); ("ru", "ruby");
    ("rs", "rust"); ("sass", "sass"); ("sc", "scala");
    ("scss", "scss"); ("sh", "bash"); ("sql", "sql"); ("svelte", "svelte");
    ("swift", "swift"); ("ts", "typescript"); ("tsx", "typescriptreact");
    ("tex", "latex"); ("toml", "toml"); ("vue", "vue"); ("vim", "vim");
    ("xml", "xml"); ("xsl", "xsl"); ("yaml", "yaml"); ("yml", "yaml");
    ("zig", "zig"); ("zon", "zig"); ("zsh", "bash"); ("c++", "cpp");
    ("erl", "erlang"); ("ex", "elixir"); ("exs", "elixir");
    ("elm", "elm"); ("fs", "fsharp"); ("fsi", "fsharp");
    ("fsx", "fsharp"); ("fsscript", "fsharp"); ("java", "java");
    ("css", "css"); ("patch", "diff");
  ]

let basename_map =
  [
    (".bash_aliases", "bash"); (".bash_logout", "bash");
    (".bash_profile", "bash"); (".bashrc", "bash"); (".kshrc", "bash");
    (".profile", "bash"); (".vimrc", "vim"); (".zlogin", "bash");
    (".zlogout", "bash"); (".zprofile", "bash"); (".zshenv", "bash");
    (".zshrc", "bash"); ("appfile", "ruby"); ("berksfile", "ruby");
    ("brewfile", "ruby"); ("cheffile", "ruby"); ("containerfile", "dockerfile");
    ("dockerfile", "dockerfile"); ("fastfile", "ruby"); ("gemfile", "ruby");
    ("gnumakefile", "make"); ("gvimrc", "vim"); ("guardfile", "ruby");
    ("makefile", "make"); ("podfile", "ruby"); ("rakefile", "ruby");
    ("thorfile", "ruby"); ("vagrantfile", "ruby");
  ]

let ext_to_filetype extension =
  List.assoc_opt (normalize_filetype_token extension) extension_map

let basename path =
  let normalized = String.map (fun c -> if Char.equal c '\\' then '/' else c) path in
  match List.rev (String.split_on_char '/' normalized) with
  | value :: _ when String.length value > 0 -> Some (String.lowercase_ascii value)
  | _ -> None

let path_to_filetype path =
  match basename (String.trim path) with
  | None -> None
  | Some basename ->
      (match List.assoc_opt basename basename_map with
      | Some filetype -> Some filetype
      | None ->
          (match String.rindex_opt basename '.' with
          | None -> None
          | Some index when index + 1 < String.length basename ->
              ext_to_filetype (String.sub basename (index + 1) (String.length basename - index - 1))
          | Some _ -> None))

let first_word value =
  let is_space character =
    Char.equal character ' ' || Char.equal character '\t'
    || Char.equal character '\r' || Char.equal character '\n'
  in
  let length = String.length value in
  let start = ref 0 in
  while !start < length && is_space (String.get value !start) do
    incr start
  done;
  let finish = ref !start in
  while !finish < length && not (is_space (String.get value !finish)) do
    incr finish
  done;
  if Int.equal !start !finish then ""
  else String.sub value !start (!finish - !start)

let info_string_to_filetype info =
  let first_word = first_word info in
  match first_word with
  | "" -> None
  | value ->
      let normalized = normalize value in
      (match List.assoc_opt normalized basename_map with
      | Some filetype -> Some filetype
      | None ->
          (match path_to_filetype normalized with
          | Some filetype -> Some filetype
          | None ->
              (match ext_to_filetype normalized with
              | Some filetype -> Some filetype
              | None -> Some (normalize_filetype_token value))))
