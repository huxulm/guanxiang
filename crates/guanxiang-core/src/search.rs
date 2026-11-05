//! 通用一维搜索：求根与求极小值。
//!
//! 事件搜索的流程是“粗搜步进找出区间 → 在区间内精修”。这里提供精修部分，
//! 粗搜的步长和剪枝由各事件类型自己决定（D2）。

use crate::error::{Error, Result};

/// 求根结果。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Root {
    pub x: f64,
    pub iterations: u32,
}

/// 极小值结果。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Minimum {
    pub x: f64,
    pub f: f64,
    pub iterations: u32,
}

const MAX_ITER: u32 = 200;

/// Brent 法求根。要求 `f(a)` 与 `f(b)` 异号（或其中之一为零）。
pub fn find_root(mut f: impl FnMut(f64) -> f64, a: f64, b: f64, tol: f64) -> Result<Root> {
    let (mut a, mut b) = (a, b);
    let (mut fa, mut fb) = (f(a), f(b));
    if fa == 0.0 {
        return Ok(Root {
            x: a,
            iterations: 0,
        });
    }
    if fb == 0.0 {
        return Ok(Root {
            x: b,
            iterations: 0,
        });
    }
    if fa.signum() == fb.signum() {
        return Err(Error::InvalidBracket("端点函数值同号"));
    }

    let (mut c, mut fc) = (a, fa);
    let mut d = b - a;
    let mut e = d;

    for iter in 1..=MAX_ITER {
        if fb.signum() == fc.signum() {
            c = a;
            fc = fa;
            d = b - a;
            e = d;
        }
        if fc.abs() < fb.abs() {
            a = b;
            b = c;
            c = a;
            fa = fb;
            fb = fc;
            fc = fa;
        }

        let tol1 = 2.0 * f64::EPSILON * b.abs() + 0.5 * tol;
        let m = 0.5 * (c - b);
        if m.abs() <= tol1 || fb == 0.0 {
            return Ok(Root {
                x: b,
                iterations: iter,
            });
        }

        if e.abs() >= tol1 && fa.abs() > fb.abs() {
            // 反二次插值或割线法
            let s = fb / fa;
            let (mut p, mut q);
            if a == c {
                p = 2.0 * m * s;
                q = 1.0 - s;
            } else {
                let qa = fa / fc;
                let r = fb / fc;
                p = s * (2.0 * m * qa * (qa - r) - (b - a) * (r - 1.0));
                q = (qa - 1.0) * (r - 1.0) * (s - 1.0);
            }
            if p > 0.0 {
                q = -q;
            } else {
                p = -p;
            }
            if 2.0 * p < (3.0 * m * q - (tol1 * q).abs()).min((e * q).abs()) {
                e = d;
                d = p / q;
            } else {
                d = m;
                e = d;
            }
        } else {
            d = m;
            e = d;
        }

        a = b;
        fa = fb;
        b += if d.abs() > tol1 { d } else { tol1.copysign(m) };
        fb = f(b);
    }

    Ok(Root {
        x: b,
        iterations: MAX_ITER,
    })
}

/// Brent 法在 `[a, b]` 内求单峰函数的极小值。
pub fn find_minimum(mut f: impl FnMut(f64) -> f64, a: f64, b: f64, tol: f64) -> Result<Minimum> {
    if a.partial_cmp(&b) != Some(std::cmp::Ordering::Less) {
        return Err(Error::InvalidBracket("要求 a < b"));
    }
    const CGOLD: f64 = 0.381_966_011_250_105_1; // (3 - √5) / 2

    let (mut a, mut b) = (a, b);
    let mut x = a + CGOLD * (b - a);
    let (mut w, mut v) = (x, x);
    let mut fx = f(x);
    let (mut fw, mut fv) = (fx, fx);
    let mut d: f64 = 0.0;
    let mut e: f64 = 0.0;

    for iter in 1..=MAX_ITER {
        let xm = 0.5 * (a + b);
        let tol1 = f64::EPSILON.sqrt() * x.abs() + tol / 3.0;
        let tol2 = 2.0 * tol1;
        if (x - xm).abs() <= tol2 - 0.5 * (b - a) {
            return Ok(Minimum {
                x,
                f: fx,
                iterations: iter,
            });
        }

        let mut golden = true;
        if e.abs() > tol1 {
            // 抛物线插值
            let r = (x - w) * (fx - fv);
            let mut q = (x - v) * (fx - fw);
            let mut p = (x - v) * q - (x - w) * r;
            q = 2.0 * (q - r);
            if q > 0.0 {
                p = -p;
            }
            q = q.abs();
            let etemp = e;
            e = d;
            if p.abs() < (0.5 * q * etemp).abs() && p > q * (a - x) && p < q * (b - x) {
                d = p / q;
                let u = x + d;
                if u - a < tol2 || b - u < tol2 {
                    d = tol1.copysign(xm - x);
                }
                golden = false;
            }
        }
        if golden {
            e = if x >= xm { a - x } else { b - x };
            d = CGOLD * e;
        }

        let u = if d.abs() >= tol1 {
            x + d
        } else {
            x + tol1.copysign(d)
        };
        let fu = f(u);

        if fu <= fx {
            if u >= x {
                a = x;
            } else {
                b = x;
            }
            (v, fv) = (w, fw);
            (w, fw) = (x, fx);
            (x, fx) = (u, fu);
        } else {
            if u < x {
                a = u;
            } else {
                b = u;
            }
            if fu <= fw || w == x {
                (v, fv) = (w, fw);
                (w, fw) = (u, fu);
            } else if fu <= fv || v == x || v == w {
                (v, fv) = (u, fu);
            }
        }
    }

    Ok(Minimum {
        x,
        f: fx,
        iterations: MAX_ITER,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_of_cubic() {
        let r = find_root(|x| x * x * x - 2.0 * x - 5.0, 2.0, 3.0, 1e-12).unwrap();
        assert!((r.x - 2.094_551_481_542_327).abs() < 1e-11, "{r:?}");
    }

    #[test]
    fn root_of_cos() {
        let r = find_root(f64::cos, 0.0, 3.0, 1e-14).unwrap();
        assert!((r.x - std::f64::consts::FRAC_PI_2).abs() < 1e-13);
    }

    #[test]
    fn root_requires_sign_change() {
        assert!(find_root(|x| x * x + 1.0, -1.0, 1.0, 1e-9).is_err());
    }

    #[test]
    fn minimum_of_parabola() {
        let m = find_minimum(|x| (x - 1.234).powi(2) + 5.0, -10.0, 10.0, 1e-10).unwrap();
        assert!((m.x - 1.234).abs() < 1e-7, "{m:?}");
        assert!((m.f - 5.0).abs() < 1e-12);
    }

    #[test]
    fn minimum_of_cos() {
        let m = find_minimum(f64::cos, 2.0, 4.0, 1e-10).unwrap();
        assert!((m.x - std::f64::consts::PI).abs() < 1e-7, "{m:?}");
    }
}
