import Foundation
import CoreGraphics

// Unambiguous CGFloat trig — some Swift toolchains flag bare `cos`/`sin`/`atan2` on
// CGFloat as ambiguous, so we route through the unambiguous `Double` overloads.
@inline(__always) func cg_cos(_ x: CGFloat) -> CGFloat { CGFloat(cos(Double(x))) }
@inline(__always) func cg_sin(_ x: CGFloat) -> CGFloat { CGFloat(sin(Double(x))) }
@inline(__always) func cg_atan2(_ y: CGFloat, _ x: CGFloat) -> CGFloat { CGFloat(atan2(Double(y), Double(x))) }
