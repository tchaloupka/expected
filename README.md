# expected

[![Latest version](https://img.shields.io/dub/v/expected.svg)](https://code.dlang.org/packages/expected)
[![Dub downloads](https://img.shields.io/dub/dt/expected.svg)](http://code.dlang.org/packages/expected)
[![Build status](https://img.shields.io/travis/tchaloupka/expected/master.svg?logo=travis&label=Travis%20CI)](https://travis-ci.org/tchaloupka/expected)
[![codecov](https://codecov.io/gh/tchaloupka/expected/branch/master/graph/badge.svg)](https://codecov.io/gh/tchaloupka/expected)
[![license](https://img.shields.io/github/license/tchaloupka/expected.svg)](https://github.com/tchaloupka/expected/blob/master/LICENSE)

Implementation of the Expected idiom.

See the [Andrei Alexandrescu’s talk (Systematic Error Handling in C++](http://channel9.msdn.com/Shows/Going+Deep/C-and-Beyond-2012-Andrei-Alexandrescu-Systematic-Error-Handling-in-C)
and [its slides](https://skydrive.live.com/?cid=f1b8ff18a2aec5c5&id=F1B8FF18A2AEC5C5!1158).

Or more recent ["Expect the Expected"](https://www.youtube.com/watch?v=nVzgkepAg5Y) by Andrei Alexandrescu for further background.

It is also inspired by C++'s proposed [std::expected](https://wg21.link/p0323) and [Rust's](https://www.rust-lang.org/) [Result](https://doc.rust-lang.org/std/result/).

Similar work is [expectations](http://code.dlang.org/packages/expectations) by Paul Backus.

Main differences with that are:

* lightweight, no other external dependencies
* allows to use same types for `T` and `E`
* allows to define `Expected` without value (`void` for `T`)
* provides facility to change the `Expected` behavior by custom `Hook` implementation using the Design by introspection.

## Features

* works with `pure`, `@safe`, `@nogc`, `nothrow`, and `immutable`
* supports `void` value type
* behavior configuration using custom `Hook` implementation and Design by introspection paradigm with safe default
* provides methods: `expected`, `unexpected`, `andThen`, `orElse`, `map`, `mapError`, `mapOrElse`

## Documentation

[View online on Github Pages](https://tchaloupka.github.io/expected/expected.html)

`expected` uses [adrdox](https://github.com/adamdruppe/adrdox) to generate it's documentation. To build your own
copy, run the following command from the root of the `expected` repository:

```BASH
path/to/adrdox/doc2 --genSearchIndex --genSource -o generated-docs source
```

## Example usage

> TODO

## Instalation

If you're using [dub](), add the [expected](https://code.dlang.org/packages/expected) package to your project as a dependency.

Alternatively, since it's a single file self-contained implementation, you can simply copy `expected.d` to your project source directory and compile as usual.

## Compilers compatibility

Build is tested against:

* dmd-2.085.1
* dmd-2.084.1
* dmd-2.083.1
* dmd-2.082.1
* dmd-2.081.2
* dmd-2.080.1
* dmd-2.079.1
* dmd-2.078.3
* dmd-2.077.1
* dmd-2.076.1
* ldc-1.15.0
* ldc-1.14.0
* ldc-1.13.0
* ldc-1.12.0
* ldc-1.11.0
* ldc-1.10.0
* ldc-1.9.0
* ldc-1.8.0
* ldc-1.7.0
* ldc-1.6.0
* dmd-beta
