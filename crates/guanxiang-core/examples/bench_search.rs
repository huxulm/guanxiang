//! 100 年事件搜索耗时（M2 性能验收：真机上一组天体对 ≤ 1 秒）。
//!
//! cargo run --release -p guanxiang-core --example bench_search -- data/de440s.bsp

use std::time::Instant;

use guanxiang_core::events::longitude::{self, Aspect};
use guanxiang_core::events::{Span, separation, transit};
use guanxiang_core::{AniseEphemeris, Body, Time};

fn main() {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "data/de440s.bsp".into());
    let eph = AniseEphemeris::from_path(&path).expect("加载星历");
    let span = Span::new(Time::from_tt_jd(2_451_544.5), Time::from_tt_jd(2_488_069.5)).unwrap();

    let time = |label: &str, f: &mut dyn FnMut() -> usize| {
        let start = Instant::now();
        let n = f();
        println!(
            "{label:<28} {n:>5} 个  {:>8.1} ms",
            start.elapsed().as_secs_f64() * 1e3
        );
    };

    for (a, b, aspect) in [
        (Body::Mercury, Body::Sun, Aspect::Conjunction),
        (Body::Mars, Body::Sun, Aspect::Opposition),
        (Body::Jupiter, Body::Saturn, Aspect::Conjunction),
        (Body::Moon, Body::Jupiter, Aspect::Conjunction),
    ] {
        let step = longitude::default_step_days(a, b);
        time(&format!("{a}-{b} {aspect:?}"), &mut || {
            longitude::search(&eph, a, b, aspect, span, step)
                .unwrap()
                .len()
        });
    }
    time("moon-venus 角距 ≤ 5°", &mut || {
        separation::search(
            &eph,
            Body::Moon,
            Body::Venus,
            span,
            separation::default_step_days(Body::Moon, Body::Venus),
            5f64.to_radians(),
        )
        .unwrap()
        .len()
    });
    time("水星凌日", &mut || {
        transit::search(&eph, Body::Mercury, span).unwrap().len()
    });
    time("金星凌日", &mut || {
        transit::search(&eph, Body::Venus, span).unwrap().len()
    });
}
