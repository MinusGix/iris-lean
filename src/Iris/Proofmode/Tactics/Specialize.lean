/-
Copyright (c) 2022 Lars König. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Lars König, Mario Carneiro
-/
import Iris.Proofmode.Tactics.Basic
import Iris.Proofmode.Tactics.Remove

namespace Iris.Proofmode
open Lean Elab Tactic Meta Qq BI Std

structure SpecializeState (prop : Q(Type)) (bi : Q(BI $prop)) (orig : Q($prop)) where
  (hyps : Hyps prop) (out : Q($prop)) (b : Q(Bool))
  pf : Q($orig ⊢ $hyps.strip ∗ □?$b $out)

theorem specialize_wand [BI PROP] {q p : Bool} {A1 A2 A3 Q P1 P2 : PROP}
    (h1 : A1 ⊢ A2 ∗ □?q Q) (h2 : A2 ⊣⊢ A3 ∗ □?p P1)
    [inst : IntoWand q p Q P1 P2] : A1 ⊢ A3 ∗ □?(p && q) P2 := by
  refine h1.trans <| (sep_mono_l h2.1).trans <| sep_assoc.1.trans (sep_mono_r ?_)
  cases p with
  | false => exact (sep_mono_r inst.1).trans wand_elim_r
  | true => exact
    (sep_mono intuitionisticallyIf_intutitionistically.2 intuitionisticallyIf_idem.2).trans <|
    intuitionisticallyIf_sep_2.trans <| intuitionisticallyIf_mono <| wand_elim' inst.1

theorem specialize_forall [BI PROP] {p : Bool} {A1 A2 P : PROP} {α : Type} {Φ : α → PROP}
    [inst : IntoForall P Φ] (h : A1 ⊢ A2 ∗ □?p P) (a : α) : A1 ⊢ A2 ∗ □?p (Φ a) := by
  refine h.trans <| sep_mono_r <| intuitionisticallyIf_mono <| inst.1.trans (forall_elim a)

def SpecializeState.process1 :
    SpecializeState prop bi orig → Term → TermElabM (SpecializeState prop bi orig)
  | { hyps, b, out, pf }, arg => do
    let name := arg.raw.getId
    if let some ⟨hyps', out₁, out₁', b1, _, pf'⟩ :=
      if name.isAnonymous then none else hyps.remove bi false arg.raw.getId
    then
      -- if the argument is a hypothesis then specialize the wand
      let b2 := if b1.constName! == ``true then b else q(false)
      have : $out₁ =Q iprop(□?$b1 $out₁') := ⟨⟩
      have : $b2 =Q ($b1 && $b) := ⟨⟩

      let out₂ ← mkFreshExprMVarQ prop
      let _ ← synthInstanceQ q(IntoWand $b $b1 $out $out₁' $out₂)
      let pf := q(specialize_wand $pf $pf')
      return { hyps := hyps', b := b2, out := out₂, pf }
    else
      -- otherwise specialize the universal quantifier
      let α ← mkFreshExprMVarQ q(Type)
      let Φ ← mkFreshExprMVarQ q($α → $prop)
      let _ ← synthInstanceQ q(IntoForall $out $Φ)
      let x ← elabTermEnsuringTypeQ (u := .succ .zero) arg α
      have out' : Q($prop) := Expr.headBeta q($Φ $x)
      have : $out' =Q $Φ $x := ⟨⟩
      return { hyps, b, out := out', pf := q(specialize_forall $pf $x) }

elab "ispecialize" hyp:ident args:(colGt term:max)* " as " name:ident : tactic => do
  -- parse syntax
  let nameFrom := hyp.getId
  if nameFrom.isAnonymous then
    throwUnsupportedSyntax

  let nameTo := name.getId
  if nameTo.isAnonymous then
    throwUnsupportedSyntax

  let (mvar, { prop, bi, hyps, goal }) ← istart (← getMainGoal)
  mvar.withContext do

  -- find hypothesis index
  let some ⟨hyps', _, out', b, _, pf⟩ := hyps.remove bi (nameFrom == nameTo) nameFrom
    | throwError "unknown hypothesis"
  let e := hyps.strip

  let state := { hyps := hyps', out := out', b, pf := q(($pf).1) }

  -- specialize hypothesis
  let { hyps, out, b, pf } ← liftM <| args.foldlM SpecializeState.process1 state
  let ehyps := hyps.strip

  let kind := if b.constName! == ``true then .intuitionistic else .spatial
  let hyp1 := .mkHyp bi kind nameTo out
  let hyps' := hyps.mkSep bi hyp1
  let ehyp1 := hyp1.strip
  have pf : Q($e ⊢ $ehyps ∗ $ehyp1) := pf
  let m : Q($ehyps ∗ $ehyp1 ⊢ $goal) ← mkFreshExprSyntheticOpaqueMVar <|
    IrisGoal.toExpr { prop, bi, hyps := hyps', goal }
  mvar.assign q(($pf).trans $m)
  replaceMainGoal [m.mvarId!]

macro "ispecialize" hyp:ident args:(colGt term:max)* : tactic =>
  `(tactic| ispecialize $hyp $args* as $hyp)
