# PCN Calculator

A fast, modern desktop calculator built with C++17 and Qt Quick (QML).

**Repository:** https://github.com/pacanekk/PCN-Calculator

## Features

- Standard and scientific modes — trig, log/ln, √, x², xʸ, |x|, eˣ, %, π, e
- Live result preview while typing
- Custom expression engine: lexer + recursive-descent parser with correct
  precedence (right-associative powers, unary minus below power)
- Full-precision result chaining — no display-rounding errors
- Scientific-notation input (e.g. `2.5e-3`) and implicit multiplication (`2π`, `3(4)`)
- Persistent calculation history with click-to-reuse
- Full keyboard support and a dark, minimal UI

## Requirements

```bash
sudo dnf install cmake gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel
```

## Build & run locally

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/pcn-calculator
```

## Tests

```bash
./build/test_engine   # or: ctest --test-dir build
```

## Install via RPM

```bash
sudo dnf install rpm-build
./build_rpm.sh
sudo dnf install pcn-calculator-*.rpm
```

Run it from the menu or type `pcn-calculator`.

## License

MIT
