//! 星历和视位置的吞吐量测试（M1 性能验收）。
//!
//! 桌面：cargo run --release -p guanxiang-core --example bench_ephemeris -- data/de440s.bsp
//! Android：cargo ndk -t arm64-v8a -P 24 build --release -p guanxiang-core --example bench_ephemeris，
//!          再用 adb push 可执行文件和 de440s.bsp 到 /data/local/tmp 运行。

use std::hint::black_box;
use std::time::Instant;

use guanxiang_core::astrometry;
use guanxiang_core::{AniseEphemeris, Body, Ephemeris, Tdb, Time};

fn main() {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "data/de440s.bsp".into());

    let t0 = Instant::now();
    let eph = AniseEphemeris::from_path(&path).expect("加载星历");
    println!("加载 {path}：{:.1} ms", t0.elapsed().as_secs_f64() * 1e3);

    // 100 年内均匀取时刻，避免只命中同一个切比雪夫记录
    let span = 100.0 * 365.25 * 86_400.0;
    let n = 1_000_000;
    let times: Vec<Tdb> = (0..n)
        .map(|i| Tdb(span * (i as f64) / (n as f64)))
        .collect();

    let pairs = [
        ("月球 相对 地球", Body::Moon, Body::Earth),
        ("太阳 相对 地球", Body::Sun, Body::Earth),
        (
            "地球 相对 太阳系质心",
            Body::Earth,
            Body::SolarSystemBarycenter,
        ),
    ];
    for (label, target, center) in pairs {
        let start = Instant::now();
        let mut acc = 0.0;
        for &t in &times {
            acc += eph.position(target, center, t).unwrap().x;
        }
        black_box(acc);
        let rate = n as f64 / start.elapsed().as_secs_f64();
        println!("{label:<20} {:>12.0} 次/秒", rate);
    }

    // 顺序时刻（搜索时的典型访问方式：相邻时刻落在同一记录内）
    let start = Instant::now();
    let mut acc = 0.0;
    for i in 0..n {
        acc += eph
            .position(Body::Moon, Body::Earth, Tdb(600.0 * i as f64))
            .unwrap()
            .x;
    }
    black_box(acc);
    println!(
        "{:<20} {:>12.0} 次/秒",
        "月球（顺序时刻）",
        n as f64 / start.elapsed().as_secs_f64()
    );

    let m = 100_000;
    let start = Instant::now();
    for i in 0..m {
        let t = Time::from_tt_seconds(span * (i as f64) / (m as f64));
        black_box(astrometry::geocentric(&eph, Body::Moon, &t).unwrap());
    }
    println!(
        "{:<20} {:>12.0} 次/秒",
        "月球地心视位置",
        m as f64 / start.elapsed().as_secs_f64()
    );
}
