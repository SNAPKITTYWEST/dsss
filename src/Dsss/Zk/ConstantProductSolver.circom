pragma circom 2.1.5;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";

// Maps SMT QF_NRA (Quantifier-Free Non-Linear Real Arithmetic)
// to a DEX invariant substrate for ZK witness generation.
// The constant-product AMM invariant (x * y = k) bounds the
// non-linear solution space, replacing dynamic DPLL(T) search
// with static arithmetic evaluation suitable for ZK circuits.
template Z3_ConstantProductSolver(nBits) {
    signal input x;
    signal input y;
    signal input constraint_target;

    // AMM invariant: bounds the non-linear solution space
    signal surface_curve <== x * y;
    surface_curve === constraint_target;

    // BitVector range constraints: prevent modular overflow attacks
    component rangeX = Num2Bits(nBits);
    rangeX.in <== x;

    component rangeY = Num2Bits(nBits);
    rangeY.in <== y;

    // Strictly bound the geometry quadrant: x > 0
    component greaterThan = GreaterThan(nBits);
    greaterThan.in[0] <== x;
    greaterThan.in[1] <== 0;
    greaterThan.out === 1;
}

component main = Z3_ConstantProductSolver(64);
