# OasisTools.jl

[![Build Status](https://github.com/Jeroen-van-der-Meer/OasisTools.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/Jeroen-van-der-Meer/OasisTools.jl/actions/workflows/ci.yml?query=branch%3Amaster)

Toolkit for working with Open Artwork System Interchange Standard (OASIS) files. Work in progress.

## Installation

```
pkg> add OasisTools
```

## Getting started

To read the contents of an OASIS file, use the `oasisread` function.

```julia
using OasisTools
filepath = joinpath(OasisTools.TESTDATA_DIRECTORY, "nested.oas");
oasisread(filepath)
```

```
OASIS file with the following cell hierarchy:
TOP
├─ BOTTOM2
│  └─ ROCKBOTTOM
├─ MIDDLE
│  ├─ BOTTOM2
│  │  └─ ⋯
│  └─ BOTTOM
└─ MIDDLE2
   └─ BOTTOM
```

It returns an `Oasis` object, which contains a list of all the cells in your OASIS file, in the form of a `Cell` object. Each cell, in turn, has a list of shapes (encoded as `Shape` objects), as well as a list of cells (i.e. placements of other cells within the specified cell).

# Caveats

- There *will* be bugs.
- Properties are currently ignored.
- Backwards-compatible extensions are not supported. You will get an error if your file contains any.
- Curvilinear features are not yet supported.
- One day there will be functionality to visually display your layout &mdash; stay tuned.
