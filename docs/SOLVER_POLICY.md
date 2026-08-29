# Solver Policy with SGMT Stylesheets

The DSSS solver is configured through **SGMT** (Sovereign Gate Meta-Tactics)
stylesheets.  An SGMT file describes *how* the solver processes queries without
touching *what* the queries mean.  This separation is Invariant I4:

> **I4 — Policy Confinement**: SGMT chooses tactics, never meaning.

If an SGMT rule altered the circuit semantics (changed which constraints are
enforced, which witnesses are accepted), that would be a bug.  SGMT rules may
only select algorithms, change representations, adjust resource limits, and emit
certificates — never alter the logical content of a query.

---

## Syntax Overview

SGMT uses a Lisp-inspired s-expression syntax with SASS-like cascade semantics:

```
(sheet <name>
  (target <backend>)
  (logic <logic-descriptor>)

  (match <selector>
    <directives...>)

  (match <selector>
    <directives...>)

  (policy <key-value-pairs...>))
```

A stylesheet is a named sheet (`liquid-default` in the example below).  The
`(target ...)` and `(logic ...)` directives set the backend and SMT-LIB logic
for the entire sheet.  `(match ...)` blocks are CSS-like selectors with
associated directives.  `(policy ...)` sets global solver knobs.

---

## The `liquid-default.sgmt` Stylesheet

The default stylesheet lives at `styles/liquid-default.sgmt`.  It is the policy
applied when DSSS processes LiquidHaskell Horn clause output:

```lisp
; DSSS Stylesheet: liquid-default
; Governs solving strategy for LiquidHaskell Horn clause output

(sheet liquid-default
  (target smtlib2)
  (logic auto)

  (match (horn-clause :linear-arithmetic true)
    (pipeline
      normalize-anf
      eliminate-let
      canonicalize-arith
      congruence-close
      solve-lia
      infer-kvars-cegar))

  (match (term :operator "mod")
    (rewrite (euclidean-mod-normal-form)))

  (match (query :kind unsat)
    (emit
      :certificate drat-like
      :diagnostics concise
      :counterexample minimized))

  (policy
    :deterministic true
    :max-refinement-rounds 32
    :seed 0
    :model-minimization lexicographic))
```

### Line-by-line explanation

#### `(sheet liquid-default ...)`

Declares the stylesheet name.  DSSS loads a stylesheet by name; the name must
match the filename stem.

#### `(target smtlib2)`

Selects the backend output format.  `smtlib2` means the solver emits standard
SMT-LIB2 alongside its internal CDCL(T) decisions, enabling interoperability
with other tools.  Other values: `internal` (no external emission), `circom`
(emit to the ZK pipeline).

#### `(logic auto)`

Lets DSSS choose the SMT-LIB logic fragment automatically based on which
theories are active.  For Horn clauses with only linear arithmetic,
`logic auto` resolves to `QF_LRA`.  If non-linear terms are present, it
resolves to `QF_NRA`.  You can override with an explicit logic name:
`(logic QF_NRA)`.

#### `(match (horn-clause :linear-arithmetic true) ...)`

The selector `(horn-clause :linear-arithmetic true)` matches all Horn clause
queries whose constraint set is purely linear.  The `:linear-arithmetic true`
attribute is set by the middleware's constraint classifier before the stylesheet
is consulted.

The matched queries are processed through the `(pipeline ...)` directive, which
specifies an ordered sequence of passes:

| Pass | Purpose |
|---|---|
| `normalize-anf` | Convert to Administrative Normal Form — all arithmetic in let-bindings |
| `eliminate-let` | Inline let-bindings after ANF to simplify the constraint graph |
| `canonicalize-arith` | Sort and collect like terms; normalise coefficients |
| `congruence-close` | Apply congruence closure to discharge trivial equalities |
| `solve-lia` | Run the Dual Simplex linear arithmetic decision procedure |
| `infer-kvars-cegar` | Infer k-variable assignments for Horn clause fixpoint via CEGAR |

This pipeline mirrors what `liquid-fixpoint` does internally, giving DSSS
compatible semantics for LiquidHaskell verification conditions.

#### `(match (term :operator "mod") ...)`

Matches any term in the query whose top-level operator is `mod` (the modulo
operation).  The directive `(rewrite (euclidean-mod-normal-form))` replaces
`a mod b` with its Euclidean normal form `a - b * floor(a/b)`, which is linear
in `a` when `b` is a constant — enabling the `solve-lia` pass to handle it.

#### `(match (query :kind unsat) ...)`

Matches queries whose final verdict is UNSAT.  The `(emit ...)` directive
controls what the solver produces:

| Attribute | Meaning |
|---|---|
| `:certificate drat-like` | Emit a DRAT-like proof certificate linked to the GADT source node |
| `:diagnostics concise` | Produce a compact human-readable explanation of the conflict |
| `:counterexample minimized` | Minimise the UNSAT core to the smallest subset of clauses |

The certificate format is DRAT-like: each certificate node carries
`certSourceType` (the GHC type fingerprint of the circuit GADT node that
generated it) and `certPolicyHash` (a hash of the SGMT rules that were applied).

#### `(policy ...)`

Global solver parameters for all queries in this sheet:

| Key | Value | Meaning |
|---|---|---|
| `:deterministic` | `true` | Disable all internal randomisation |
| `:max-refinement-rounds` | `32` | CEGAR loop: maximum fixpoint refinement iterations |
| `:seed` | `0` | Random seed (used only if `:deterministic false`) |
| `:model-minimization` | `lexicographic` | When multiple models exist, choose the lex-smallest |

`:deterministic true` + `:seed 0` + `:model-minimization lexicographic` together
guarantee that the same query produces the same model on every run, on every
machine.  This is required for the `certPolicyHash` to be stable.

---

## SASS-Style CSS Selectors for the Lowering Pass

After SSA construction and before theory expansion, the lowering pass applies a
second selector language with CSS-attribute syntax.  These selectors target
individual word nodes in the lowered SSA graph:

```scss
/* Ripple-carry adder for small buses (≤16 bits) */
word[op="WAdd"][width<="16"] {
    lower: ripple;
    proof: local-adder;
}

/* Carry-lookahead for larger buses */
word[op="WAdd"][width>="17"] {
    lower: carry-lookahead;
    proof: prefix-adder;
}

/* Safety properties: use k-induction */
property[kind="Always"] {
    engine: k-induction;
    k: 4;
}

/* Deep state machines: use PDR / IC3 */
state-cone[register-count>="8"] {
    engine: pdr;
}
```

### Selector attributes

| Attribute | Type | Matches |
|---|---|---|
| `op` | string | `WordOp` constructor name (e.g. `WAdd`, `WXor`, `WMux`) |
| `width` | nat (with `<=`, `>=`, `=`) | `wordWidth` field of `WordNode` |
| `kind` | string | Property kind: `Always`, `Eventually`, `Reachability` |
| `register-count` | nat | Number of registers in the state cone of a node |

These selectors are applied in order (last match wins, as in CSS).  If no rule
matches a node, the default strategy is used: word operators default to
`lower: aig` (AIG-based), properties default to `engine: bmc` (bounded model
checking).

### Proof terms

The `proof:` attribute names the proof certificate type attached to the lowered
node.  Available terms:

| Proof term | Description |
|---|---|
| `local-adder` | Local correctness proof: sum and carry equations for a single-stage adder |
| `prefix-adder` | Prefix tree proof: parallel carry-lookahead correctness |
| `bmc-k` | Bounded model checking certificate up to depth k |
| `k-induction-k` | k-induction certificate |
| `pdr-invariant` | PDR/IC3 inductive invariant |

---

## Writing Your Own Stylesheet

### Template

```lisp
(sheet my-policy
  (target smtlib2)
  (logic QF_NRA)                    ; or auto

  ; Match non-linear queries
  (match (horn-clause :non-linear true)
    (pipeline
      normalize-anf
      eliminate-let
      canonicalize-arith
      solve-nra-groebner))          ; use Gröbner basis for NRA

  ; All results get full certificates
  (match (query :kind unsat)
    (emit
      :certificate drat-like
      :diagnostics verbose
      :counterexample minimized))

  (match (query :kind sat)
    (emit
      :model full
      :certificate none))

  (policy
    :deterministic true
    :max-refinement-rounds 64
    :seed 0
    :model-minimization lexicographic))
```

### Rules for correct stylesheets

1. Always include `(policy :deterministic true :seed 0)`.  Non-deterministic
   solves produce non-reproducible certificates.
2. Never use `(rewrite ...)` in a way that changes satisfiability — only
   equivalence-preserving rewrites are permitted (I4).
3. If you add a new `(match ...)` block, document the constraint class it
   targets with a semicolon comment.
4. The `(logic ...)` directive must be consistent with the theories used.
   Setting `(logic QF_LRA)` for a query that contains `x*y` will produce an
   error — use `QF_NRA` or `auto`.
5. SASS selectors in the lowering pass are applied after ANF normalisation.
   Selectors targeting `op="WAdd"` will not match before normalisation converts
   `CAdd` gates to `WAdd` word nodes.

---

## Stylesheet Lookup Order

DSSS looks for stylesheets in this order:

1. The path passed explicitly via `--stylesheet <path>`
2. `styles/<name>.sgmt` relative to the project root
3. The built-in `liquid-default` (compiled into the solver)

If no stylesheet is found, DSSS falls back to the built-in defaults: `logic
auto`, no pipeline override, DRAT-like certificates, deterministic with seed 0.

---

## Further Reading

- `styles/liquid-default.sgmt` — the default stylesheet, annotated
- `spec/LOWERING_SPEC.md` — full list of `WordOp` constructors, graph strata,
  and which nodes the SASS selectors target
- `spec/ARCHITECTURE.md` — how the stylesheet interacts with the CDCL(T) core
  and the five theory solvers
