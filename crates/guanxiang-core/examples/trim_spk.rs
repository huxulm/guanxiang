//! 按时间范围裁剪 SPK 星历（M7：缩小安装包）。
//!
//! cargo run --release -p guanxiang-core --example trim_spk -- data/de440s.bsp data/de440s_1900_2100.bsp 1899-12-01 2101-02-01
//!
//! 只删除范围外的整条切比雪夫记录，不重算系数，所以范围内的位置与原文件逐位一致；
//! 写出后会重新加载两份文件，在范围内随机取时刻比较所有天体的位置。

use std::time::Instant;

use anise::naif::SPK;
use anise::naif::daf::datatypes::Type2ChebyshevSet;
use anise::naif::daf::{DafDataType, NAIFDataSet, NAIFSummaryRecord};
use anise::time::Epoch;
use guanxiang_core::{AniseEphemeris, Body, DateTime, Ephemeris, Tdb, Time};

fn tdb_seconds(s: &str) -> f64 {
    let d: DateTime = s.parse().expect("日期格式 YYYY-MM-DD");
    Time::from_utc(&d).expect("日期").tdb().0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 5 {
        eprintln!("用法：trim_spk <输入.bsp> <输出.bsp> <起始 UTC 日期> <结束 UTC 日期>");
        std::process::exit(2);
    }
    let (input, output) = (&args[1], &args[2]);
    let (start_s, end_s) = (tdb_seconds(&args[3]), tdb_seconds(&args[4]));
    let (start, end) = (
        Epoch::from_et_seconds(start_s),
        Epoch::from_et_seconds(end_s),
    );

    let t0 = Instant::now();
    // 读一份、改一份：裁剪后的段借用 `src` 的数据，写进 `dst`
    let src = SPK::load(input).expect("读取输入文件");
    let mut dst = SPK::load(input).expect("读取输入文件");
    let summaries = src.data_summaries(None).expect("段摘要").to_vec();
    println!("{input}：{} 段", summaries.len());
    // 段长度（双精度个数）
    let len = |spk: &SPK, i: usize| {
        let s = spk.data_summaries(None).unwrap()[i];
        s.end_index() + 1 - s.start_index()
    };
    let mb = |n: usize| n as f64 * 8.0 / 1e6;
    let mut removed = 0usize;
    for (i, s) in summaries.iter().enumerate() {
        if s.is_empty() {
            continue;
        }
        assert!(
            matches!(s.data_type(), Ok(DafDataType::Type2ChebyshevTriplet)),
            "第 {i} 段不是 Type 2（只支持 Type 2）"
        );
        let new_start = (s.start_epoch_et_s() < start_s).then_some(start);
        let new_end = (s.end_epoch_et_s() > end_s).then_some(end);
        let set = src
            .nth_data::<Type2ChebyshevSet>(None, i)
            .expect("读取段数据");
        let set = set.truncate(s, new_start, new_end).expect("裁剪");
        let first = set.init_epoch;
        let last = first + set.interval_length * set.num_records as f64;
        let before = len(&dst, i);
        dst.set_nth_data(i, set, first, last).expect("写回段数据");
        let after = len(&dst, i);
        removed += before - after;
        println!(
            "  段 {i:2}：目标 {:4} 中心 {:2}，{:.1} MB → {:.1} MB",
            s.target_id,
            s.center_id,
            mb(before),
            mb(after)
        );
    }
    dst.persist(output).expect("写出文件");
    fix_free_pointer(input, output, removed);
    let in_size = std::fs::metadata(input).unwrap().len();
    let out_size = std::fs::metadata(output).unwrap().len();
    println!(
        "{output}：{:.1} MB（原 {:.1} MB），用时 {:.1} s",
        out_size as f64 / 1e6,
        in_size as f64 / 1e6,
        t0.elapsed().as_secs_f64()
    );

    // 校验：两份文件在范围内的位置逐位一致
    let full = AniseEphemeris::from_path(input).expect("重新加载输入");
    let trimmed = AniseEphemeris::from_path(output).expect("加载输出");
    let (cs, ce) = trimmed.coverage(Body::Moon).expect("覆盖范围");
    println!(
        "月球覆盖：{} 至 {}",
        Time::from_tdb(cs).to_utc().unwrap(),
        Time::from_tdb(ce).to_utc().unwrap()
    );
    let n = 200_000;
    let mut max_diff = 0.0f64;
    let mut state = 0x9E37_79B9_7F4A_7C15u64;
    for _ in 0..n {
        // xorshift，避免引入随机数依赖
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let t = Tdb(start_s
            + 86_400.0
            + (end_s - start_s - 2.0 * 86_400.0) * (state as f64 / u64::MAX as f64));
        for b in Body::ALL {
            if b == Body::Sun {
                continue;
            }
            let a = full.position(b, Body::Sun, t).expect("原文件");
            let c = trimmed.position(b, Body::Sun, t).expect("裁剪后");
            max_diff = max_diff.max((a - c).norm());
        }
    }
    println!("随机 {n} 个时刻、全部天体的位置差最大 {max_diff:e} km");
    assert!(max_diff == 0.0, "裁剪后位置应逐位一致");
}

/// anise 的 `set_nth_data`/`persist` 不更新文件记录里的 FREE（第一个空闲双精度地址），
/// 而 SPICE、jplephem 都靠它确定数据末尾。按删除的双精度个数修正。
/// DAF 文件记录：LOCIDW(8) ND(4) NI(4) LOCIFN(60) FWARD(4) BWARD(4) FREE(4) LOCFMT(8)。
fn fix_free_pointer(input: &str, output: &str, removed: usize) {
    const FREE: usize = 84;
    let src = std::fs::read(input).expect("读取输入");
    let mut out = std::fs::read(output).expect("读取输出");
    assert_eq!(&src[88..96], b"LTL-IEEE", "只处理小端文件");
    let old = i32::from_le_bytes(src[FREE..FREE + 4].try_into().unwrap());
    let new = old - i32::try_from(removed).expect("删除量");
    // 数据之后不应再有内容：新的 FREE 对应的字节位置不能超出文件
    assert!((new as usize - 1) * 8 <= out.len(), "FREE 超出文件长度");
    out[FREE..FREE + 4].copy_from_slice(&new.to_le_bytes());
    std::fs::write(output, out).expect("写回输出");
    println!("FREE 指针：{old} → {new}");
}
