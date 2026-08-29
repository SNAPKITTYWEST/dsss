# Security Policy

## Supported Versions

DSSS is currently in its initial research release.  The following table reflects
the versions that receive security fixes:

| Version | Supported |
|---|---|
| `main` branch (unreleased) | Yes |
| v0.1.x | Yes |
| Earlier tags / snapshots | No |

---

## What Counts as a Security Issue for DSSS

DSSS is a formal-verification and zero-knowledge proof system.  Correctness
failures in its core components constitute security vulnerabilities because
downstream consumers may rely on certificates, witnesses, or proofs produced by
DSSS to make trust decisions.  The following categories are in scope:

### 1. Solver Soundness Bugs

A soundness bug occurs when the solver returns **SAT** (or a proof certificate)
for a query that is actually **UNSAT**, or when a lowered circuit violates one of
the six core invariants (I1–I6) without raising an error.  Examples:

- The CDCL(T) core accepts a model that violates a theory constraint.
- A `LowerCert` is emitted with an incorrect `certWidth` that does not match the
  GADT source type index `w`.
- `CheckWire` fails to detect a mismatched width at compile time due to a type
  family soundness hole.
- Width reification (`reifyWidth`) permits a zero-width node without throwing
  `ZeroWidthCircuit`.

### 2. ZK Circuit Completeness and Soundness Holes

The Circom ZK pipeline must satisfy obligations P1–P6 (see
`spec/ZK_QF_NRA_SPEC.md`).  A security issue occurs when:

- The circuit is **not sound**: an invalid witness satisfies the R1CS constraints
  (a prover can generate a proof for a false statement).
- The circuit is **not complete**: a valid witness fails to satisfy the R1CS
  constraints (a legitimate prover cannot generate a proof).
- The `Num2Bits` or `GreaterThan` range constraints can be bypassed, allowing
  modular overflow or out-of-range signals.
- The `surface_curve === constraint_target` constraint is not correctly enforced
  in the compiled R1CS.

### 3. Certificate Forgery

A `LowerCert` (or any DRAT-like certificate emitted by the solver) must be
unforgeable in the sense that it is structurally tied to its source node via the
`certSourceType` fingerprint and `certPolicyHash`.  A vulnerability exists if:

- A certificate for node A can be replayed as a valid certificate for a different
  node B without detection.
- The `certPolicyHash` can be computed without access to the actual SGMT policy
  that was applied, allowing policy substitution attacks.
- The structural induction proof (P1: parser output isomorphic to SMT-LIB input)
  can be violated by a crafted SMT-LIB string.

### 4. Side-Channel Leaks in the ZK Witness Pipeline

The ZK witness pipeline must not leak private witness values (`x`, `y`) beyond
the public input `k`.  A vulnerability exists if:

- Timing differences in the Scala parser or Circom witness calculator correlate
  with private signal values.
- The generated OpenSCAD polyhedron leaks information beyond the public geometry
  (i.e., the shape reveals `x` or `y` independently of `k` in a way not intended
  by the protocol).
- Intermediate values are written to disk or logged in a recoverable form.
- The `seed=0` deterministic replay mechanism produces outputs that differ
  between solver invocations on identical inputs, indicating non-deterministic
  state leakage.

---

## How to Report a Vulnerability

**Do NOT open a public GitHub Issue for security vulnerabilities.**

Instead, report privately by email to:

> **BEL ESPRIT D ACCORD TRUST HOLDINGS INC**
> Security disclosures: contact via the repository owner's profile on GitHub
> (send a private message or email if listed).

Your report should include:

1. A clear description of the vulnerability class (from the categories above, or
   a new category you have identified).
2. The affected component(s): file paths, function names, and/or circuit
   identifiers.
3. A minimal reproducer — a crafted input, a test case, or a proof sketch that
   demonstrates the issue.
4. Your assessment of exploitability and impact (e.g., "a prover can forge a
   satisfying witness for an unsatisfiable query").
5. Whether you have a proposed fix (optional but appreciated).

Please encrypt sensitive disclosures if you have a PGP key for the contact
address.

---

## Response Timeline

| Event | Target |
|---|---|
| Acknowledgement of receipt | Within **48 hours** |
| Initial triage and severity assessment | Within **7 days** |
| Patch or mitigation for **Critical** issues | Within **30 days** |
| Patch or mitigation for **High** issues | Within **60 days** |
| Patch or mitigation for **Medium / Low** issues | Best-effort; typically next release |
| Public disclosure (coordinated) | After patch is available and deployed |

We follow coordinated disclosure.  If you wish to publish a write-up, please
allow us to release the fix before public disclosure.  We will credit you in the
changelog unless you prefer to remain anonymous.

---

## Severity Classification

| Severity | Examples |
|---|---|
| **Critical** | Solver returns SAT for an UNSAT query; ZK circuit soundness hole that allows proof forgery |
| **High** | Certificate forgery; private witness leakage through a side channel |
| **Medium** | Completeness failure that prevents a legitimate prover from succeeding; determinism violation |
| **Low** | Informational leakage in error messages; non-exploitable internal assertion failure |

---

## Contact

**BEL ESPRIT D ACCORD TRUST HOLDINGS INC**

All security communications related to DSSS should reference this project and the
version number affected.  For non-security bugs, please use
[GitHub Issues](https://github.com/SNAPKITTYWEST/dsss/issues).
