# OasisTools.jl

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

For large files, pass `lazy = true`: the cells are then only decoded from the file as and when they are needed, and their shapes are never all held in memory at once. See [Lazy loading](@ref) for how this works. All of the examples below work the same either way.

Coordinates are integers, in the database units of the file; `OasisTools.unit(oas)` tells you how many of them make a micron. (GeometryBasics, which provides `Rect` and `Point`, also exports a function called `unit`, hence the `OasisTools.` in front.)

### Cropping a region

[`crop`](@ref) cuts out the part of a cell that lies within a box, and returns it as a new layout.

```julia
using OasisTools, GeometryBasics

oas = oasisread("chip.oas"; lazy = true)
um(x) = round(Int64, x * OasisTools.unit(oas)) # Microns to database units

# A box given by its lower-left corner, and then its width and height.
window = Rect{2, Int64}(Point{2, Int64}(um(100), um(250)), Point{2, Int64}(um(50), um(50)))
oasiswrite("chip_cropped.oas", crop(oas, :TOP, window))
```

### Finding all instances of a cell

[`find_instances`](@ref) lists every instance of a cell anywhere in the hierarchy below a top cell, in the coordinates of that top cell. Cells can be given by name, or by a regular expression.

```julia
using OasisTools

oas = oasisread("chip.oas"; lazy = true)
instances = find_instances(oas, r"^NAND2_"; top = :TOP)

open("nand2.csv", "w") do io
    println(io, "cell,x_um,y_um,rotation,magnification,flipped")
    for p in instances
        x, y = p.location ./ OasisTools.unit(oas)
        println(io, join((p.cell, x, y, p.rotation, p.magnification, p.flipped), ","))
    end
end
```

### Extracting a single layer

[`filter_shapes!`](@ref) keeps only the shapes you ask for. The cell hierarchy stays as it is, so cells without any shapes on the layer end up empty.

```julia
using OasisTools

oas = oasisread("chip.oas"; lazy = true)
filter_shapes!(s -> s.layer == 17 && s.datatype == 0, oas)
oasiswrite("chip_layer_17.oas", oas)
```

### Placing one layout into another

[`merge_oases`](@ref) combines the cells of several layouts, after which a cell of one can be placed in a cell of another.

```julia
using OasisTools, GeometryBasics

chip = oasisread("chip.oas"; lazy = true)
logo = oasisread("logo.oas"; lazy = true)
combined = merge_oases(chip, logo)
add_placement!(combined[:TOP], :LOGO, Point{2, Int64}(-4000, -4000)) # LOGO is the top cell of logo.oas
oasiswrite("chip_with_logo.oas", combined)
```

Both files must use the same database units, and their cells must have different names; [`merge_oases`](@ref) throws an error otherwise. To resolve a clash, rename cells first with [`rename_cell!`](@ref), which also updates the placements of the renamed cell.

# Caveats

- There *will* be bugs.
- Properties are currently ignored, and left out when writing.
- Extension records (XNAME, XELEMENT and XGEOMETRY) are skipped, with a warning.
- Curvilinear features are not yet supported.
