open Monadic
open Rws

 module RWSTest = struct
  type 'a tree = Leaf of 'a | Branch of 'a tree * 'a * 'a tree

  module GenError = Result.Make(struct type t = string end)
  module StringMon = struct
    type t = string
    let empty = ""
    let append = (^)
  end
  module GenM = MakeT(GenError)(Int)(StringMon)(Int)

  let rec rws_test f =
    let open GenM.Syntax in
    let open GenM in function
      | Leaf v ->
        let* env = peek in
        let* _ = "Leaf with: " ^ string_of_int (f v) ^ "\n" |> tell in
        let* s = get in
        let* _ = put (env * (f v) + s) in
        get
      | Branch (l, v, r) ->
        let* ls = rws_test f l in
        let* _ = "Branch with: " ^ string_of_int (f v) ^ "\n" |> tell in
        let* s = get in
        let* _ = put (s - (f v)) in
        let* rs = rws_test f r in
        if ls <= rs
        then elevate @@ GenError.error "This must not be"
        else get

  let testtree = Branch (Leaf 3, 4, Leaf 5)

  let id x = x
  let test1 = GenM.run (rws_test id testtree) ~r:1 ~s:0
  let test2 = GenM.run (rws_test id testtree) ~r:(-1) ~s:0
end
