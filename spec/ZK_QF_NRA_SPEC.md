# ZK-QF_NRA Solver — Formal Specification

## Objective

Construct a zero-knowledge circuit that decides bounded Quantifier-Free
Non-Linear Real Arithmetic (QF_NRA) constraints from LiquidHaskell refinement
types. The circuit statically encodes the SMT-LIB fragment, imposes the DEX
AMM invariant x·y = k as the core non-linear theory, and extracts the witness
to generate a 3D CAD model via trigonometric sweep.

## Primitive Definitions

| Symbol | Meaning | Domain |
|--------|---------|--------|
| n | Bit-width for fixed-point | ℕ (64 in production, 16 in demo) |
| fb | Fractional bits (scale = 2^fb) | ℕ (32 production, 8 demo) |
| x, y | AMM reserve signals (private) | 𝔽_{2^n} unsigned, fixed-point |
| k | Constant-product target (public) | Same domain as x·y |
| Range_n(z) | Bit-decomposition: 0 ≤ z < 2^n | Via Num2Bits |
| GT_n(a,b) | a > b comparator | Via GreaterThan |
| θ, φ | Spherical sweep angles | θ∈[0,2π), φ∈[0,π] |

## Algorithm

```
Input: LiquidHaskell refinement → SMT-LIB string S
Output: OpenSCAD source file SCAD

1. Parse S (fastparse) → AST A
2. Translate A → Circom signal netlist N:
   a. Vars → public/private signals
   b. Nums → constant signals
   c. Binary ops → intermediate signals via <==
   d. Comparisons → comparator components, output constrained to 1
   e. Each reserve (x, y) → Num2Bits(n) + GreaterThan(n)
3. Insert DEX core: signal surface <== x * y; surface === k;
4. Compile circuit → R1CS + witness calculator
5. Run witness calculator with public k → obtain (x_s, y_s)
6. Divide by 2^fb → unscaled witness (x, y)
7. Trigonometric sweep: for i,j in [0,steps):
     θ = i·2π/steps, φ = j·π/steps
     emit (x·sinφ·cosθ, y·sinφ·sinθ, x·y·cosφ)
8. Triangulate and emit OpenSCAD polyhedron
```

## Proof Obligations

| ID | Statement | Method |
|----|-----------|--------|
| P1 | Parser returns AST isomorphic to input SMT-LIB | Structural induction on grammar |
| P2 | Circom netlist enforces same relation as AST | Induction on AST depth |
| P3 | `surface === x·y ∧ surface === k` iff x·y = k | Direct field equality |
| P4 | Num2Bits guarantees 0 ≤ x,y < 2^n; GT guarantees x>0 | circomlib correctness |
| P5 | Sweep points lie on surface X·Y = (x·y)sin²φ | Parametric substitution |
| P6 | Circuit reveals only public input k | Standard Groth16/PLONK ZK property |

## Concrete Demo (nBits=16, fb=8, x=20, y=30)

- Scaled inputs: x_s = 5120, y_s = 7680
- k = 5120 × 7680 = 39,321,600
- Unscaled witness: (20, 30)
- CAD amplitudes: X-radius=20, Y-radius=30, Z-radius=±600

## Novelty Status

**POSSIBLY_NOVEL** — The specific composition of:
1. Static QF_NRA solver built from DEX AMM invariants inside a ZK circuit
2. Witness extraction driving a trigonometric CAD generator
3. Formal proof obligations linking witness to generated geometry

has not been identified in existing public ZK-SMT or ZK-geometry works.
