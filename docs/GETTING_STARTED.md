# Getting Started with DSSS

This guide walks you from a fresh clone to a running end-to-end demo that
generates a ZK witness and renders the constraint polyhedron in OpenSCAD.

---

## Prerequisites

Install the following before you begin.  The guide gives quick-start commands
for each; see [CONTRIBUTING.md](../CONTRIBUTING.md) for more detail.

| Tool | Minimum version | Check command |
|---|---|---|
| Git | any recent | `git --version` |
| GHC | 9.4 | `ghc --version` |
| Cabal | 3.8 | `cabal --version` |
| Idris 2 | 0.7.0 | `idris2 --version` |
| Futhark | 0.25.0 | `futhark --version` |
| Scala / sbt | Scala 3.3 | `sbt --version` |
| Node.js | 18 LTS | `node --version` |
| circom | 2.1.5 | `circom --version` |
| snarkjs | 0.7 | `snarkjs --version` |
| Python | 3.10+ | `python3 --version` |
| OpenSCAD | 2021.01+ | `openscad --version` |

Quick installs (macOS / Linux):

```bash
# Haskell toolchain
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc 9.4.8 && ghcup set ghc 9.4.8

# Idris 2 (via pack)
curl https://www.idris-lang.org/install/pack.bash | bash
pack install idris2

# Futhark
curl https://futhark-lang.org/install.sh | sh

# Scala / sbt (via SDKMAN)
curl -s "https://get.sdkman.io" | bash
sdk install java 17.0.9-tem && sdk install sbt

# Circom + snarkjs
npm install -g circom snarkjs

# OpenSCAD (Debian/Ubuntu)
sudo apt install openscad
# macOS: brew install openscad
```

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/SNAPKITTYWEST/dsss.git
cd dsss
```

---

## Step 2 — Build the Haskell Circuit Library

The Haskell source lives in `src/Dsss/Circuit/`.  It compiles with Cabal:

```bash
cabal update
cabal build all
```

Expected output:

```
Build profile: -w ghc-9.4.8 -O1
In order, the following will be built (use -v for more details):
 - dsss-0.1.0 (lib) (first run)
[1 of 9] Compiling Dsss.Circuit.TypeNat
[2 of 9] Compiling Dsss.Circuit.Vec
[3 of 9] Compiling Dsss.Circuit.Core
[4 of 9] Compiling Dsss.Circuit.Gate
[5 of 9] Compiling Dsss.Circuit.DSL
[6 of 9] Compiling Dsss.Circuit.Builder
[7 of 9] Compiling Dsss.Circuit.Lower.Pass
[8 of 9] Compiling Dsss.Frontend.CADModel   -- (Idris 2 elaboration)
[9 of 9] Compiling Dsss.Backend.kernel      -- (Futhark compilation)
```

If GHC rejects a type error in your working tree, it is almost certainly a real
width-invariant violation — read the diagnostic carefully.  The `CheckWire` type
family emits a structured message that names the upstream and downstream widths.

---

## Step 3 — Type-Check the Idris 2 Frontend

```bash
idris2 --check src/Dsss/Frontend/CADModel.idr
idris2 --check src/Dsss/Frontend/TypeNet.idr
```

No output means success.  A type error means a QTT multiplicity or depth
invariant has been violated.

---

## Step 4 — Compile the Futhark Kernel

For CPU-only development (no GPU required):

```bash
futhark c src/Dsss/Backend/kernel.fut -o build/kernel
```

For OpenCL (AMD / Intel / NVIDIA):

```bash
futhark opencl src/Dsss/Backend/kernel.fut -o build/kernel_ocl
```

For CUDA:

```bash
futhark cuda src/Dsss/Backend/kernel.fut -o build/kernel_cuda
```

---

## Step 5 — Compile the Scala Parser

```bash
sbt compile
```

The Scala component parses LiquidHaskell SMT-LIB2 output and emits Circom
signal netlists.  After compilation, run its tests:

```bash
sbt test
```

---

## Step 6 — Compile the Circom ZK Circuit

The ZK circuit is at `src/Dsss/Zk/ConstantProductSolver.circom`.  It implements
the DEX constant-product invariant `x · y = k` as a ZK circuit parameterised by
`nBits`.  The production parameterisation is `nBits=64`; for the demo we use
`nBits=16` (smaller witness, faster build).

Create the output directory and compile:

```bash
mkdir -p build/zk

circom src/Dsss/Zk/ConstantProductSolver.circom \
  --r1cs \
  --wasm \
  --sym \
  --output build/zk/
```

You should see:

```
template instances: 1
non-linear constraints: 65
linear constraints: 0
public inputs: 1
public outputs: 0
private inputs: 2
wires: 196
labels: 196
Written successfully: build/zk/ConstantProductSolver.r1cs
Written successfully: build/zk/ConstantProductSolver.sym
Written successfully: build/zk/ConstantProductSolver_js/ConstantProductSolver.wasm
Written successfully: build/zk/ConstantProductSolver_js/witness_calculator.js
```

---

## Step 7 — Generate the ZK Witness

Create an `input.json` file for the demo witness (x=20, y=30, scaled by 2^8=256
because `fb=8`, so `x_s=5120`, `y_s=7680`, `k=x_s*y_s=39321600`):

```bash
cat > input.json <<'EOF'
{
  "x": "5120",
  "y": "7680",
  "constraint_target": "39321600"
}
EOF
```

Compute the witness:

```bash
node build/zk/ConstantProductSolver_js/generate_witness.js \
     build/zk/ConstantProductSolver_js/ConstantProductSolver.wasm \
     input.json \
     build/zk/witness.wtns
```

Export the witness to JSON to inspect the signal values:

```bash
snarkjs wtns export json build/zk/witness.wtns build/zk/witness.json
cat build/zk/witness.json
```

The unscaled coordinates are recovered by dividing by `2^fb = 256`:

```
x_unscaled = 5120 / 256 = 20
y_unscaled = 7680 / 256 = 30
k_unscaled = 20 * 30 = 600
```

These are the radii used in the OpenSCAD polyhedron sweep.

---

## Step 8 — View the OpenSCAD Polyhedron

The pre-generated demo geometry is already in the repository:

```bash
openscad examples/demo_constraint_polyhedron.scad
```

The file renders a trigonometric sweep of the surface `X·Y = (x·y)sin²φ`, which
is the geometric visualisation of the constant-product invariant with the witness
values as bounding amplitudes (X=20, Y=30, Z-amplitude=600).

To regenerate it from the Scala compiler with your own witness values, edit
`TrigCADCompiler.emitOpenSCAD` in `src/Dsss/Zk/ConstraintSolver.scala` and run:

```bash
sbt "runMain dsss.zk.TrigCADCompilerMain --x 20 --y 30 --steps 50"
```

---

## Step 9 — Run All Tests

```bash
# Haskell
cabal test

# Idris 2 (type-check is the test)
idris2 --check src/Dsss/Frontend/CADModel.idr
idris2 --check src/Dsss/Frontend/TypeNet.idr

# Futhark
futhark test src/Dsss/Backend/kernel.fut

# Scala
sbt test

# Python
python3 -m pytest src/Dsss/Theory/
```

---

## Directory Structure

```
dsss/
├── src/Dsss/
│   ├── Backend/kernel.fut          Futhark parallel constraint kernel
│   ├── Circuit/
│   │   ├── Core.hs                 Wire, Bus, Port, Signal GADTs
│   │   ├── DSL.hs                  Circuit GADT + CheckWire type family
│   │   ├── Gate.hs                 Gate constructors + ValidSlice
│   │   ├── TypeNat.hs              Width/Depth/Arity synonyms, Assert/NonZero/Fits
│   │   ├── Vec.hs                  Size-indexed bit vector
│   │   ├── Builder.hs              Build monad, node emission
│   │   └── Lower/Pass.hs           LowerM monad, proof obligations, certificates
│   ├── Frontend/
│   │   ├── CADModel.idr            Idris 2 QTT recursive CAD model
│   │   └── TypeNet.idr             Type Net bipartite graph
│   ├── Theory/Trig.py              Taylor interval + SingleCellCAD solver
│   └── Zk/
│       ├── ConstraintSolver.scala  SMT-LIB parser + TrigCAD emitter
│       └── ConstantProductSolver.circom  DEX AMM ZK circuit
├── styles/liquid-default.sgmt      SGMT solver policy stylesheet
├── spec/                           Formal specifications (read before contributing)
├── examples/
│   ├── demo_constraint_polyhedron.scad  Pre-generated witness geometry
│   └── demo_*.gif                  Animated render screenshots
└── docs/                           User guides (you are here)
```

---

## Troubleshooting

**GHC type error about `CheckWire`**
: You have connected two circuit components whose bus widths do not match.  Read
  the error: it shows `Upstream output bus width` and `Downstream input bus
  width` explicitly.  Fix the width of the intermediate component.

**`ZeroWidthCircuit` exception at runtime**
: A `KnownNat` witness resolved to zero inside the lowering pass.  This is a bug
  in how you constructed the circuit — the type must have been insufficiently
  constrained.  Add an explicit `NonZero w` constraint.

**`circom` fails with "include not found"**
: Install `circomlib` locally: `npm install circomlib` then rerun with
  `--include node_modules`.

**OpenSCAD renders a blank window**
: The `steps` variable is 0 or the `points` array is empty.  Ensure the witness
  values are non-zero before calling `TrigCADCompiler.emitOpenSCAD`.

**Futhark: "no GPU available"**
: Use `futhark c` for a CPU build during development.  The parallel backend is
  not required to run the demo.
