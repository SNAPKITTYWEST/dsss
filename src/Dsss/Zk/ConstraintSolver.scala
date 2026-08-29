// DSSS: SMT-LIB to Circuit AST parser
// LiquidHaskell emits refinement types as Horn clauses → SMT-LIB
// This maps them to Circom signal inputs for ZK witness generation

import fastparse._, SingleLineWhitespace._

sealed trait SMTExpr
case class SMTVar(name: String)                        extends SMTExpr
case class SMTNum(value: Int)                          extends SMTExpr
case class SMTApp(op: String, args: Seq[SMTExpr])      extends SMTExpr

object LiquidHaskellSMTParser {
  def symbol[_: P]: P[SMTVar] =
    P(CharIn("a-zA-Z") ~ CharIn("a-zA-Z0-9_").rep).!.map(SMTVar)

  def number[_: P]: P[SMTNum] =
    P("-".? ~ CharIn("0-9").rep(1)).!.map(s => SMTNum(s.toInt))

  def expr[_: P]: P[SMTExpr] =
    P(symbol | number | "(" ~ symbol.! ~ expr.rep(1) ~ ")").map {
      case v: SMTVar               => v
      case n: SMTNum               => n
      case (op: String, args: Seq[SMTExpr @unchecked]) => SMTApp(op, args)
    }

  def assertion[_: P]: P[SMTExpr] = P("(assert" ~ expr ~ ")")

  def parseSMT(input: String): Parsed[SMTExpr] = parse(input, assertion(_))
}

// Trigonometric CAD geometry from constraint bounds
object TrigCADCompiler {
  def emitOpenSCAD(xBound: Double, yBound: Double, steps: Int = 50): String = {
    val sb = new StringBuilder
    sb.append("// Auto-generated Z3 Constraint Polyhedron via DEX Invariants\n")
    sb.append("polyhedron(\n points = [\n")

    for (i <- 0 until steps; j <- 0 until steps) {
      val theta = (i * 2.0 * math.Pi) / steps
      val phi   = (j * math.Pi) / steps
      val x = xBound * math.sin(phi) * math.cos(theta)
      val y = yBound * math.sin(phi) * math.sin(theta)
      val z = (xBound * yBound) * math.cos(phi)
      sb.append(s"  [$x, $y, $z],\n")
    }

    sb.append(" ],\n faces = [\n")
    for (i <- 0 until steps - 1; j <- 0 until steps - 1) {
      val p1 = i * steps + j
      val p2 = p1 + 1
      val p3 = p1 + steps
      val p4 = p3 + 1
      sb.append(s"  [$p1, $p2, $p4, $p3],\n")
    }
    sb.append(" ]\n);")
    sb.toString()
  }
}
