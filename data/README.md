# data

星历等大文件放在这里，不进 Git。

```sh
curl -fL -o data/de440s.bsp https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
```

也可以用环境变量 `GUANXIANG_EPHEM` 指定其他路径（测试时要用绝对路径，测试的工作目录是各 crate 目录）。

App 打包的是裁剪到 1900–2100 年的版本：

```sh
cargo run --release -p guanxiang-core --example trim_spk -- data/de440s.bsp data/de440s_1900_2100.bsp 1899-12-01 2101-02-01
```

结果可复现，SHA-256 为 `1b7ff150cbc00d364f584ad65dad651129fde4ab2e7aa23f9551dc9b9674afaa`。CI 每次都会重新生成并校验。
