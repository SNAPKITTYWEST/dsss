# DSSS Full Architecture

## The Unified Judgment

Geometric constraints, type shape constraints, and resource usage constraints
are expressed in a single multi-sorted logic:

- **Sorts**: Real, SO3 (rotations), SE3 (rigid transforms), Shape[n], Constraint
- **Multiplicities**: QTT annotations q ∈ {0,1,ω} — erased, linear, unrestricted
- **Recursion**: Fixed-points bounded by depth parameters with 0-multiplicity (compile-time only)

The Type Net bridges type system and constraint system: it is both a type artifact
(checked by Idris 2 QTT) and a constraint artifact (solved by SMT core).

## Four-Layer Stack

```
┌──────────────────────────────────────────────────────┐
│ FRONTEND: Idris 2 + QTT                              │
│  ├─ Type Net (0-multiplicity shape params)            │
│  ├─ Recursive CAD model (bounded depth)               │
│  └─ Futhark-invariant array contracts                 │
└────────────────────┬─────────────────────────────────┘
                     │ elaboration
                     ▼
┌──────────────────────────────────────────────────────┐
│ MIDDLEWARE: Type Net Compiler                         │
│  ├─ GADT → Futhark size-dependent types               │
│  ├─ QTT multiplicity → runtime/erased/linear tagging  │
│  └─ Constraint graph → SMT-LIB + geometric extensions │
└────────────────────┬─────────────────────────────────┘
                     │ translation
                     ▼
┌──────────────────────────────────────────────────────┐
│ SOLVER CORE: CDCL(T)                                  │
│  ├─ SAT Core (2-watched literals, VSIDS, CDCL)        │
│  ├─ Theory 1: LRA  — Dual Simplex                     │
│  ├─ Theory 2: NRA  — Single-cell CAD + Gröbner        │
│  ├─ Theory 3: Trig — Taylor intervals + phase unwrap  │
│  ├─ Theory 4: Geom — SO(3)/SE(3) propagation          │
│  └─ Theory 5: TypeNet — size graph propagation        │
└────────────────────┬─────────────────────────────────┘
                     │ fixed-point iteration
                     ▼
┌──────────────────────────────────────────────────────┐
│ BACKEND: Parallel Constraint Kernel (Futhark)         │
│  ├─ Batch SAT checks on GPU arrays                    │
│  ├─ In-place constraint buffer updates (uniqueness)   │
│  └─ Recursive model unfolding with bounded depth      │
└──────────────────────────────────────────────────────┘
```

## SMT-LIB Extension

```smtlib
(declare-sort SO3 0)
(declare-sort SE3 0)
(declare-sort Mesh 1)  ; size-parameterized

(declare-fun sin (Real) Real)
(declare-fun cos (Real) Real)
(declare-fun rotation (Real Real Real) SO3)
(declare-fun rigid (SO3 Real Real Real) SE3)

(declare-size n Int)
(declare-size m Int)
(assert-size (= n (+ (* 2 m) 1)))

(define-recursive-fun assembly ((d Int)) Mesh[n]
  (ite (<= d 0)
       base-mesh
       (union (assembly (- d 1))
              (transform (assembly (- d 1)) T))))
```

## Recursive Fixed-Point with Widening

```
solve_fixed_point(model, max_depth=10):
    current = ⊤  (unconstrained)
    for i in 0..max_depth:
        next = model.step(current)
        if next ⊑ current:          -- subsumption check
            return SAT, current     -- fixed point reached
        current = widening(current, next)
        if smt_check(current) == UNSAT:
            return UNSAT, extract_core()
    return UNKNOWN
```

## Complexity

| Component | Complexity | Bottleneck |
|-----------|-----------|------------|
| SAT Core | Exponential (worst) | Boolean structure |
| LRA (Simplex) | Polynomial | Pivot operations |
| NRA (Single-cell CAD) | Single exponential | Real root isolation |
| Trig linearization | Linear per iteration | Taylor evaluation |
| TypeNet propagation | O(\|V\| + \|E\|) | Graph traversal |
| Futhark batch eval | O(n) parallel | GPU memory bandwidth |

## Known Limitations

1. **Trig completeness**: Taylor linearization is incomplete for transcendental
   constraints. Lindemann-Weierstrass machinery is beyond practical SMT.
2. **Recursive termination**: SAT at bounded depth does not guarantee SAT of
   the infinite model (only UNSAT is sound if unsat core is depth-independent).
3. **QTT inference**: Full QTT inference for geometric DSLs requires elaborator
   engineering beyond current Idris 2 capabilities.
4. **Theory combination**: Trigonometric theory is not stably infinite in the
   Nelson-Oppen sense — requires careful shared-variable handling with LRA.
