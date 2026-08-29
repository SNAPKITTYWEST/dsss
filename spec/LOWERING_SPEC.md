# DSSS Lowering Pass — Formal Specification

## Contract

```haskell
lowerCircuit
  :: forall g w.
     CircuitModule g
  -> TypedNode g w
  -> LowerM (LoweredWord g w)
```

The type index `w` is preserved from source to target. A malformed circuit
(width mismatch, out-of-bounds slice, non-1-bit mux select) cannot enter
lowering — the GADT constructor has already established the invariant.

## Pass Order

```
Typed Circuit GADT
  -> Hash-cons and validate reflected widths
  -> Normalize structural operators
  -> Partition combinational and state regions
  -> Produce SSA word graph
  -> Attach SGMT/SASS-selected lowering policy
  -> Expand selected nodes into bit/AIG/word constraints
  -> Generate proof obligations and certificates
```

## Width Equations per Constructor

```
CAnd x y    => width(x) = width(y) = width(result)
CMux s x y  => width(s) = 1, width(x) = width(y) = width(result)
CConcat x y => width(result) = width(x) + width(y)
CSlice x h l => 0 <= l <= h < width(x), width(result) = h - l + 1
CEq x y     => width(x) = width(y), width(result) = 1
CReg r x    => width(state[r]) = width(x) = width(result)
```

A violation is an **internal compiler bug**, not a user error.

## Structural Rewrites (width-preserving)

```
not(not x)          -> x
and(x, all-ones[w]) -> x
and(x, zero[w])     -> zero[w]
xor(x, zero[w])     -> x
xor(x, x)           -> zero[w]
mux(1, t, f)        -> t
mux(0, t, f)        -> f
mux(s, x, x)        -> x
eq(x, x)            -> one[1]
ult(x, x)           -> zero[1]
```

## Graph Strata

```
Inputs       : environment-controlled values
StateRead    : current-state registers
Combinational: acyclic function of Inputs + StateRead
StateWrite   : next-state equations
Properties   : one-bit assertions over graph nodes
```

Cyclic SCCs in Comb nodes are rejected. Sequential cycles are legal only
if each feedback path crosses a StateRead→StateWrite boundary.

## SASS Policy Selection (post-lowering, pre-theory-expansion)

```scss
word[op="WAdd"][width<="16"]  { lower: ripple; proof: local-adder; }
word[op="WAdd"][width>="17"]  { lower: carry-lookahead; proof: prefix-adder; }
property[kind="Always"]       { engine: k-induction; k: 4; }
state-cone[register-count>="8"] { engine: pdr; }
```

Policy chooses representations, never alters circuit semantics.

## Six Core Invariants

```
I1. Width preservation:   lower : Circuit g w -> LoweredWord g w
I2. Graph separation:     combinational nodes form a DAG
I3. State discipline:     every temporal feedback crosses a register
I4. Policy confinement:   SASS chooses tactics, never meaning
I5. Replayability:        every node has a certificate to its typed source
I6. Property sort:        safety predicates consume only Word g 1
```

## Theory Solvers

| Theory | Algorithm | Domain |
|--------|-----------|--------|
| LRA | Dual Simplex | Linear Real Arithmetic |
| NRA | Single-cell CAD + Gröbner | Non-Linear Real Arithmetic |
| Trig | Taylor intervals + phase unwrapping | Trigonometric constraints |
| Geom | SO(3)/SE(3) constraint propagation | Geometric invariants |
| TypeNet | Constraint graph propagation | Shape/size parameters |

## Parallel Backend (Futhark)

```futhark
def check_constraints [n] (shapes: [n][3]f64) (transforms: [n][4][4]f64) : [n]bool =
    map2 (\s T ->
        let det   = det4x4 T
        let ortho = is_orthogonal T
        let bounded = all (\x -> x > 0 && x < 1e6) s
        in det > 0.999 && det < 1.001 && ortho && bounded
    ) shapes transforms
```

## Frontend (Idris 2 QTT)

Recursive CAD models with bounded depth, QTT multiplicity for
compile-time/erased/linear distinction:

```idris
data CADModel : (depth : Nat) -> Type where
    Primitive : (0 d : Nat) -> Mesh -> CADModel d
    Transform : (1 m : CADModel d) -> (0 R : SO3) -> (0 t : R3) -> CADModel d
    Union     : (1 a : CADModel d) -> (1 b : CADModel d) -> CADModel d
    Recurse   : (0 d : Nat) -> (1 f : CADModel d -> CADModel (S d)) -> CADModel (S d)
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
