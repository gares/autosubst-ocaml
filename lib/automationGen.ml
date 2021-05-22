open GallinaGen
open Util

module TacGen = struct
  open Ltac_plugin.Tacexpr

  type t = raw_tactic_expr
  type locus_clause_expr = Names.lident Locus.clause_expr

  let default_locus_clause = Locus.{ onhyps = Some []; concl_occs = AllOccurrences}
  let star_locus_clause = Locus.{ onhyps = None; concl_occs = AllOccurrences}

  let idtac_ = TacId []
  let rewrite_ ?(repeat_star=true) ?(with_evars=false) ?(to_left=false) ?(locus_clause=default_locus_clause) name =
    let num_rewrite = if repeat_star
      then Equality.RepeatStar
      else Equality.Precisely 1 in
    let rewrite_term = [ (not to_left, num_rewrite, (None, (ref_ name, Tactypes.NoBindings))) ] in
    TacAtom (CAst.make (TacRewrite (with_evars, rewrite_term, locus_clause, None)))

  let repeat_ tactic = TacRepeat tactic
  let first_ tactics = TacFirst tactics
  let progress_ tactic = TacProgress tactic
  let try_ tactic = TacTry tactic
  let calltac_ name = TacArg (CAst.make (Reference (qualid_ name)))
  let calltacArgs_ name args =
    let args = List.map (fun s -> Reference (qualid_ s)) args in
    TacArg (CAst.make (TacCall (CAst.make (qualid_ name, args))))
  let calltacTac_ name tac =
    TacArg (CAst.make (TacCall (CAst.make (qualid_ name, [ Tacexp tac ]))))
  let then1_ tactic1 tactic2 = TacThen (tactic1, tactic2)
  let then_ = function
    | [] -> idtac_
    | tac :: tacs ->
      List.fold_left (fun t1 t2 -> then1_ t1 t2) tac tacs
  let cbn_ consts =
    let consts = List.map (fun s ->
        CAst.make (Constrexpr.AN (qualid_ s))) consts in
    let delta = list_empty consts in
    let flags : Genredexpr.r_cst Genredexpr.glob_red_flag = {
      rBeta = true;
      rMatch = true;
      rFix = true;
      rCofix = true;
      rZeta = true;
      rDelta = delta;
      rConst = consts;
    } in
    let cbn = Genredexpr.Cbn flags in
    TacAtom (CAst.make (TacReduce (cbn, default_locus_clause)))

  let intros_ names =
    let intro_pats = List.map (fun s ->
        CAst.make (Tactypes.IntroNaming (Namegen.IntroIdentifier (name_id_ s))))
        names in
    let intros = TacAtom (CAst.make (TacIntroPattern (false, intro_pats))) in
    intros

  let unfold_ ?(locus_clause=default_locus_clause) lemmas =
    let consts = List.map (fun s ->
        CAst.make (Constrexpr.AN (qualid_ s))) lemmas in
    let occ_list = List.map (fun c -> (Locus.AllOccurrences, c)) consts in
    let unfold = Genredexpr.Unfold occ_list in
    TacAtom (CAst.make (TacReduce (unfold, locus_clause)))

  (* let notation_ cexpr =
   *   TacArg (CAst.make (ConstrMayEval (Genredexpr.ConstrTerm cexpr))) *)

  let pr_tactic_ltac name tactic =
    let open Ltac_plugin.Pptactic in
    let env = Global.env () in
    let sigma = Evd.from_env env in
    let pp = pr_raw_tactic env sigma tactic in
    Pp.(seq [ str "Ltac "; str name; str " := "; pp; vernacend; newline ])

  let pr_tactic_notation names tactic =
    let open Ltac_plugin.Pptactic in
    let env = Global.env () in
    let sigma = Evd.from_env env in
    let pp = pr_raw_tactic env sigma tactic in
    Pp.(seq (str "Tactic Notation " :: (List.map (fun n -> str (n ^ " ")) names) @ [ str ":= "; pp; vernacend; newline ]))
end

module NotationGen = struct
  open Vernacexpr

  type g_assoc = Gramlib.Gramext.g_assoc = NonA | RightA | LeftA

  type t = NG_VarConstr of string * string
         | NG_VarInst of string * string
         | NG_Var
         | NG_Up of string
         | NG_SubstApply of string * string
         | NG_Subst of string
         | NG_RenApply of string * string
         | NG_Ren of string

  let subst_scope = "subst_scope"
  let fscope = "fscope"

  let level_ l = SetLevel l
  let assoc_ a = SetAssoc a
  let format_ fmt = SetFormat ("text", CAst.make fmt)
  let only_print_ = SetOnlyPrinting

  let notation_string n =
    let open Printf in
    match n with
    | NG_VarConstr (var, sort)
    | NG_VarInst (var, sort) ->
      sprintf "%s '__%s'" var sort
    | NG_Var ->
      "'var'"
    | NG_Up sort ->
      sprintf "↑__%s" sort
    | NG_SubstApply (var, sigma) ->
      sprintf "%s [ %s ]" var sigma
    | NG_Subst sigma ->
      sprintf "[ %s ]" sigma
    | NG_RenApply (var, sigma) ->
      sprintf "%s ⟨ %s ⟩" var sigma
    | NG_Ren sigma ->
      sprintf "⟨ %s ⟩" sigma

  let notation_modifiers n =
    let open Printf in
    match n with
    | NG_VarConstr (var, sort) ->
      let fmt = sprintf "%s __%s" var sort in
      [ level_ 5; format_ fmt ]
    | NG_VarInst (var, sort) ->
      let fmt = sprintf "%s __%s" var sort in
      [ level_ 5; format_ fmt; only_print_ ]
    | NG_Var ->
      [ level_ 1; only_print_ ]
    | NG_Up sort ->
      [ only_print_ ]
    | NG_SubstApply _
    | NG_RenApply _ ->
      [ level_ 7; assoc_ LeftA; only_print_ ]
    | NG_Subst _
    | NG_Ren _ ->
      [ level_ 1; assoc_ LeftA; only_print_ ]

  let notation_scope = function
    | NG_VarConstr _ | NG_VarInst _ | NG_Var | NG_Up _
    | NG_SubstApply _ | NG_RenApply _ ->
      subst_scope
    | NG_Subst _ | NG_Ren _ ->
      fscope
end

module ClassGen = struct
  type t = Ren of int
         | Subst of int
         | Var
         | Up of string

  let instance_name sort = function
    | Ren _ -> sep "Ren" sort
    | Subst _ -> sep "Subst" sort
    | Var -> sep "VarInstance" sort
    | Up bsort -> sepd [ "Up"; bsort; sort ]

  let class_name sort = function
    | Ren n -> "Ren"^(string_of_int n)
    | Subst n -> "Subst"^(string_of_int n)
    | Var -> "Var"
    | Up _ -> sep "Up" sort

  (* a.d. TODO, maybe directly put constr_expr in the info instead of generating the function name here  *)
  let function_name sort = function
    | Ren _ -> sep "ren" sort
    | Subst _ -> sep "subst" sort
    | Var -> CoqNames.var_ sort
    | Up bsort -> sepd ["up"; bsort; sort]

  let class_args x =
    let us n = list_of_length underscore_ n in
    match x with
    | Ren n | Subst n -> us (n + 2)
    | Var | Up _ -> us 2

  let class_field sort = function
    | Ren n -> "ren"^(string_of_int n)
    | Subst n -> "subst"^(string_of_int n)
    | Var -> "ids"
    | Up _ -> sep "up" sort

  let instance_unfolds sort x =
    [ instance_name sort x; class_name sort x; class_field sort x ]
end

type t = {
  asimpl_rewrite_lemmas : string list;
  asimpl_cbn_functions : string list;
  asimpl_unfold_functions : string list;
  substify_lemmas : string list;
  auto_unfold_functions : string list;
  arguments : (string * string list) list;
  classes : (ClassGen.t * string) list;
  (* instance info probably also needs parameter information *)
  instances : (ClassGen.t * string) list;
  notations : (NotationGen.t * constr_expr) list;
}

let initial = {
  asimpl_rewrite_lemmas = [];
  asimpl_cbn_functions = [];
  asimpl_unfold_functions = ["up_ren"];
  substify_lemmas = [];
  auto_unfold_functions = [];
  arguments = [];
  classes = [];
  instances = [];
  notations = [];
}

let asimpl_rewrite_lemmas info = info.asimpl_rewrite_lemmas
let asimpl_cbn_functions info = info.asimpl_cbn_functions
let asimpl_unfold_functions info = info.asimpl_unfold_functions
let substify_lemmas info = info.substify_lemmas
let auto_unfold_functions info = info.auto_unfold_functions
let arguments info = info.arguments
let classes info = info.classes
let instances info = info.instances
let notations info = info.notations