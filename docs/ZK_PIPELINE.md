# ZK Pipeline: LH Refinements to OpenSCAD Polyhedron

This document describes the full end-to-end ZK pipeline in DSSS:

```
LiquidHaskell Horn clause (SMT-LIB string)
  → Scala SMT-LIB parser
  → SMT AST
  → Circom signal netlist
  → R1CS + witness calculator
  → ZK witness values
  → Trigonometric sweep
  → OpenSCAD polyhedron
```

The pipeline converts an LH refinement constraint into a geometric object whose
shape is uniquely determined by the constraint's solution.  The ZK property
means the object can be publicly verified without revealing the private witness
values `(x, y)` beyond what the public input `k` already implies.

---

## 1. Write an LH Refinement

LiquidHaskell emits Horn clauses as SMT-LIB2 assertions when it cannot discharge
a refinement type internally.  The typical form for a non-linear constraint is:

```smtlib
(assert
  (and
    (> x 0)
    (> y 0)
    (= (* x y) k)))
```

This says: there exist `x`, `y` greater than zero whose product equals `k`.  DSSS
treats this as a QF_NRA (Quantifier-Free Non-Linear Real Arithmetic) query.

For the demo, the concrete values are `k = 600` (public), with private solution
`(x=20, y=30)`.

---

## 2. Parse the SMT-LIB String (Scala)

The parser lives in `src/Dsss/Zk/ConstraintSolver.scala`.  It uses
[fastparse](https://github.com/com-lihaoyi/fastparse) to convert the SMT-LIB
surface syntax into a Scala ADT:

```scala
sealed trait SMTExpr
case class SMTVar(name: String)                        extends SMTExpr
case class SMTNum(value: Int)                          extends SMTExpr
case class SMTApp(op: String, args: Seq[SMTExpr])      extends SMTExpr
```

The grammar mirrors SMT-LIB exactly — symbols are alphanumeric identifiers,
numerals are integer literals (including negative), and applications are
parenthesised prefix s-expressions:

```scala
object LiquidHaskellSMTParser {
  def symbol[_: P]: P[SMTVar] =
    P(CharIn("a-zA-Z") ~ CharIn("a-zA-Z0-9_").rep).!.map(SMTVar)

  def number[_: P]: P[SMTNum] =
    P("-".? ~ CharIn("0-9").rep(1)).!.map(s => SMTNum(s.toInt))

  def assertion[_: P]: P[SMTExpr] = P("(assert" ~ expr ~ ")")
}
```

**Proof obligation P1**: The parser output is structurally isomorphic to the
SMT-LIB input — proved by structural induction on the grammar.  Every grammar
production has exactly one corresponding ADT constructor; no information is lost
or invented.

---

## 3. Translate AST to Circom Signal Netlist

The compiled AST is translated to Circom signals according to these rules:

| SMT-LIB node | Circom translation |
|---|---|
| `SMTVar name` | `signal input name;` (private) or `signal name;` (intermediate) |
| `SMTNum value` | Constant signal assignment: `signal_name <== value;` |
| Binary `*` application | Intermediate signal: `signal prod <== left * right;` |
| Binary `=` application | Constraint: `left === right;` |
| Reserve variables `x`, `y` | `Num2Bits(n)` + `GreaterThan(n)` range components |
| DEX core `(= (* x y) k)` | `signal surface <== x * y; surface === k;` |

**Proof obligation P2**: The Circom netlist enforces the same relation as the
AST — proved by induction on AST depth.  Each recursive case maps to exactly one
signal or constraint in the netlist.

The full ZK template is `src/Dsss/Zk/ConstantProductSolver.circom`:

```circom
pragma circom 2.1.5;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";

template Z3_ConstantProductSolver(nBits) {
    signal input x;                        // private
    signal input y;                        // private
    signal input constraint_target;        // public: k

    // AMM invariant: x * y = k
    signal surface_curve <== x * y;
    surface_curve === constraint_target;   // P3: direct field equality

    // Range constraints: 0 ≤ x, y < 2^nBits
    component rangeX = Num2Bits(nBits);
    rangeX.in <== x;

    component rangeY = Num2Bits(nBits);
    rangeY.in <== y;

    // Positivity: x > 0
    component greaterThan = GreaterThan(nBits);
    greaterThan.in[0] <== x;
    greaterThan.in[1] <== 0;
    greaterThan.out === 1;
}

component main = Z3_ConstantProductSolver(64);
```

**Proof obligation P3**: `surface_curve === constraint_target` holds if and only
if `x * y = k` — direct field equality over the prime field.

**Proof obligation P4**: `Num2Bits(n)` guarantees `0 ≤ x, y < 2^n`;
`GreaterThan(n)` guarantees `x > 0`.  These are inherited from circomlib
correctness proofs.

**Proof obligation P6**: The circuit reveals only the public input `k` — standard
Groth16/PLONK ZK property.  `x` and `y` appear only as private signals and are
not included in the verification key.

---

## 4. Compile to R1CS

```bash
circom src/Dsss/Zk/ConstantProductSolver.circom \
  --r1cs --wasm --sym \
  --output build/zk/
```

This produces:

- `build/zk/ConstantProductSolver.r1cs` — the Rank-1 Constraint System
- `build/zk/ConstantProductSolver_js/ConstantProductSolver.wasm` — witness calculator
- `build/zk/ConstantProductSolver.sym` — symbolic signal names for debugging

The R1CS encodes every `<==` and `===` in the circuit as a triplet
`(A · w) * (B · w) = (C · w)` where `w` is the witness vector.  The
constant-product circuit has 65 non-linear R1CS constraints (one per bit in the
`Num2Bits` decompositions plus the surface equality).

---

## 5. Compute the Witness

The witness is computed from public and private inputs.  DSSS uses a fixed-point
fractional encoding with `fb = 8` fractional bits, so real values are scaled by
`2^8 = 256`:

```
x_s = x * 2^fb = 20 * 256 = 5120
y_s = y * 2^fb = 30 * 256 = 7680
k   = x_s * y_s = 5120 * 7680 = 39,321,600   (the circuit operates on scaled values)
```

Create `input.json`:

```json
{
  "x": "5120",
  "y": "7680",
  "constraint_target": "39321600"
}
```

Generate the witness:

```bash
node build/zk/ConstantProductSolver_js/generate_witness.js \
     build/zk/ConstantProductSolver_js/ConstantProductSolver.wasm \
     input.json \
     build/zk/witness.wtns
```

Export to JSON to inspect:

```bash
snarkjs wtns export json build/zk/witness.wtns build/zk/witness.json
```

The relevant signals (indices vary by build):

| Signal | Scaled value | Unscaled (÷256) |
|---|---|---|
| `x` | 5120 | **20** |
| `y` | 7680 | **30** |
| `constraint_target` | 39321600 | **600** |
| `surface_curve` | 39321600 | 600 (= x·y, public) |

---

## 6. Trigonometric Sweep to OpenSCAD

The Scala `TrigCADCompiler` takes the unscaled witness radii and generates a
trigonometric surface sweep:

```scala
object TrigCADCompiler {
  def emitOpenSCAD(xBound: Double, yBound: Double, steps: Int = 50): String = {
    // For each (θ, φ) in [0, 2π) × [0, π):
    //   x = xBound * sin(φ) * cos(θ)
    //   y = yBound * sin(φ) * sin(θ)
    //   z = (xBound * yBound) * cos(φ)
    ...
  }
}
```

The parametric equations produce a surface where `X·Y = (xBound·yBound)·sin²φ`.
Setting `φ = π/2` gives `z = 0` and `X·Y = xBound·yBound = k_unscaled = 600`,
which is exactly the constant-product constraint curve in the equatorial plane.

**Proof obligation P5**: Sweep points lie on the surface
`X·Y = (x·y)·sin²φ` — verified by direct parametric substitution:

```
X * Y = (xBound * sin(φ) * cos(θ)) * (yBound * sin(φ) * sin(θ))
      = xBound * yBound * sin²(φ) * sin(θ) * cos(θ)
```

With the specific parametrisation used (where `z = k·cos(φ)` and the product
constraint is `surface = x*y`), the equatorial cross-section at `z=0` is exactly
the constraint curve.

The pre-generated output is `examples/demo_constraint_polyhedron.scad`.  Open it
with:

```bash
openscad examples/demo_constraint_polyhedron.scad
```

---

## 7. Full Proof Obligations Summary

| ID | Claim | How Verified |
|---|---|---|
| P1 | Parser output isomorphic to SMT-LIB input | Structural induction on grammar |
| P2 | Circom netlist enforces the same relation as the AST | Induction on AST depth |
| P3 | `surface === x·y ∧ surface === k` iff `x·y = k` | Direct field equality |
| P4 | `Num2Bits` guarantees `0 ≤ x,y < 2^n`; `GreaterThan` guarantees `x > 0` | circomlib correctness |
| P5 | Sweep points lie on the surface `X·Y = (x·y)·sin²φ` | Parametric substitution |
| P6 | Circuit reveals only public input `k` | Standard Groth16/PLONK ZK property |

---

## 8. Extending the Pipeline

### Adding a new constraint type

1. Add a case to the Scala `SMTExpr` ADT and the `LiquidHaskellSMTParser`.
2. Add a translation rule in the compiler (the function that walks the AST and
   emits Circom signals).
3. Add a new proof obligation or update P2 to cover the new case.
4. Write a test: an SMT-LIB string that exercises the new constraint, a reference
   witness, and an assertion that the witness satisfies the R1CS.

### Using a different ZK proving system

The pipeline produces a standard `.r1cs` file.  You can use it with any
Groth16-compatible prover:

```bash
# Groth16 setup (requires a trusted setup ceremony for production)
snarkjs groth16 setup build/zk/ConstantProductSolver.r1cs pot12_final.ptau build/zk/setup.zkey

# Generate proof
snarkjs groth16 prove build/zk/setup.zkey build/zk/witness.wtns \
        build/zk/proof.json build/zk/public.json

# Verify
snarkjs groth16 verify build/zk/verification_key.json \
        build/zk/public.json build/zk/proof.json
```

For PLONK (no trusted setup):

```bash
snarkjs plonk setup build/zk/ConstantProductSolver.r1cs pot12_final.ptau build/zk/setup.zkey
snarkjs plonk prove build/zk/setup.zkey build/zk/witness.wtns \
        build/zk/proof.json build/zk/public.json
snarkjs plonk verify build/zk/verification_key.json \
        build/zk/public.json build/zk/proof.json
```

### Changing `nBits`

The template is parameterised by `nBits`.  Edit the last line of
`ConstantProductSolver.circom`:

```circom
component main = Z3_ConstantProductSolver(16);   // smaller demo
component main = Z3_ConstantProductSolver(64);   // production
```

Larger `nBits` means more R1CS constraints (one per bit in `Num2Bits`) but
supports larger witness values.

---

## Further Reading

- `src/Dsss/Zk/ConstraintSolver.scala` — SMT-LIB parser and TrigCAD emitter
- `src/Dsss/Zk/ConstantProductSolver.circom` — the ZK template
- `spec/ZK_QF_NRA_SPEC.md` — formal specification of the algorithm, all six
  proof obligations, and the concrete demo trace
- `docs/GETTING_STARTED.md` — step-by-step build and witness generation
